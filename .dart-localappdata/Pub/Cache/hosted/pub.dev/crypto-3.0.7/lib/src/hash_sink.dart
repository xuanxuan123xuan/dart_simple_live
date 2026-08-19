// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

import 'digest.dart';
import 'utils.dart';

/// A base class for [Sink] implementations for hash algorithms.
///
/// Subclasses should override [updateHash] and [digest].
abstract class HashSink implements Sink<List<int>> {
  /// The inner sink that this should forward to.
  final Sink<Digest> _sink;

  /// Whether the hash function operates on big-endian words.
  final Endian _endian;

  /// A [ByteData] view of the current chunk of data.
  ///
  /// This is an instance variable to avoid re-allocating.
  ByteData? _byteDataView;

  /// The actual chunk of bytes currently accumulating.
  ///
  /// The same allocation will be reused over and over again; once full it is
  /// passed to the underlying hashing algorithm for processing.
  final Uint8List _chunk;

  /// The index of the next insertion into the chunk.
  int _chunkNextIndex;

  /// A [Uint32List] (in specified endian) copy of the chunk.
  ///
  /// This is an instance variable to avoid re-allocating.
  final Uint32List _chunk32;

  /// Messages with more than 2^53-1 bits are not supported.
  ///
  /// This is the largest value that is precisely representable
  /// on both JS and the Dart VM.
  /// So the maximum length in bytes is (2^53-1)/8.
  static const _maxMessageLengthInBytes = 0x0003ffffffffffff;

  /// The length of the input data so far, in bytes.
  int _lengthInBytes = 0;

  /// Whether [close] has been called.
  bool _isClosed = false;

  /// The words in the current digest.
  ///
  /// This should be updated each time [updateHash] is called.
  Uint32List get digest;

  /// The number of signature bytes emitted at the end of the message.
  ///
  /// An encrypted message is followed by a signature which depends
  /// on the encryption algorithm used. This value specifies the
  /// number of bytes used by this signature. It must always be
  /// a power of 2 and no less than 8.
  final int _signatureBytes;

  /// Creates a new hash.
  ///
  /// [chunkSizeInWords] represents the size of the input chunks processed by
  /// the algorithm, in terms of 32-bit words.
  HashSink(
    this._sink,
    int chunkSizeInWords, {
    Endian endian = Endian.big,
    int signatureBytes = 8,
  })  : _endian = endian,
        assert(signatureBytes >= 8),
        _signatureBytes = signatureBytes,
        _chunk = Uint8List(chunkSizeInWords * bytesPerWord),
        _chunkNextIndex = 0,
        _chunk32 = Uint32List(chunkSizeInWords);

  /// Runs a single iteration of the hash computation, updating [digest] with
  /// the result.
  ///
  /// [chunk] is the current chunk, whose size is given by the
  /// `chunkSizeInWords` parameter passed to the constructor.
  void updateHash(Uint32List chunk);

  @override
  void add(List<int> data) {
    if (_isClosed) throw StateError('Hash.add() called after close().');
    _lengthInBytes += data.length;
    _addData(data);
  }

  void _addData(List<int> data) {
    var dataIndex = 0;
    var chunkNextIndex = _chunkNextIndex;
    final size = _chunk.length;
    _byteDataView ??= _chunk.buffer.asByteData();
    while (true) {
      // Check if there is enough data left in [data] for a full chunk.
      var restEnd = chunkNextIndex + data.length - dataIndex;
      if (restEnd < size) {
        // There is not enough data, so just add into [_chunk].
        _chunk.setRange(chunkNextIndex, restEnd, data, dataIndex);
        _chunkNextIndex = restEnd;
        return;
      }

      // There is enough data to fill the chunk. Fill it and process it.
      _chunk.setRange(chunkNextIndex, size, data, dataIndex);
      dataIndex += size - chunkNextIndex;

      // Now do endian conversion to words.
      var j = 0;
      do {
        _chunk32[j] = _byteDataView!.getUint32(j * bytesPerWord, _endian);
        j++;
      } while (j < _chunk32.length);

      updateHash(_chunk32);
      chunkNextIndex = 0;
    }
  }

  @override
  void close() {
    if (_isClosed) return;
    _isClosed = true;

    _finalizeAndProcessData();
    assert(_chunkNextIndex == 0);
    _sink.add(Digest(_byteDigest()));
    _sink.close();
  }

  Uint8List _byteDigest() {
    if (_endian == Endian.host) return digest.buffer.asUint8List();

    // Cache the digest locally as `get` could be expensive.
    final cachedDigest = digest;
    final byteDigest = Uint8List(cachedDigest.lengthInBytes);
    final byteData = byteDigest.buffer.asByteData();
    for (var i = 0; i < cachedDigest.length; i++) {
      byteData.setUint32(i * bytesPerWord, cachedDigest[i]);
    }
    return byteDigest;
  }

  /// Finalizes the data and finishes the hash.
  ///
  /// This adds a 1 bit to the end of the message, and expands it with 0 bits to
  /// pad it out.
  void _finalizeAndProcessData() {
    if (_lengthInBytes > _maxMessageLengthInBytes) {
      throw UnsupportedError(
        'Hashing is unsupported for messages with more than 2^53 bits.',
      );
    }

    final contentsLength = _lengthInBytes + 1 /* 0x80 */ + _signatureBytes;
    final finalizedLength = _roundUp(
      contentsLength,
      _chunk.lengthInBytes,
    );

    // Prepare the finalization data.
    var padding = Uint8List(finalizedLength - _lengthInBytes);
    // Pad out the data with 0x80, eight or sixteen 0s, and as many more 0s
    // as we need to land cleanly on a chunk boundary.
    padding[0] = 0x80;

    // The rest is already 0-bytes.

    var lengthInBits = _lengthInBytes * bitsPerByte;

    // Add the full length of the input data as a 64-bit value at the end of the
    // hash. Note: we're only writing out 64 bits, so skip ahead 8 if the
    // signature is 128-bit.
    final offset = padding.length - 8;
    var byteData = padding.buffer.asByteData();

    // We're essentially doing byteData.setUint64(offset, lengthInBits, _endian)
    // here, but that method isn't supported on dart2js so we implement it
    // manually instead.
    var highBits = lengthInBits ~/ 0x100000000; // >> 32
    var lowBits = lengthInBits & mask32;
    if (_endian == Endian.big) {
      byteData.setUint32(offset, highBits, _endian);
      byteData.setUint32(offset + bytesPerWord, lowBits, _endian);
    } else {
      byteData.setUint32(offset, lowBits, _endian);
      byteData.setUint32(offset + bytesPerWord, highBits, _endian);
    }

    _addData(padding);
  }

  /// Rounds [val] up to the next multiple of [n], as long as [n] is a power of
  /// two.
  int _roundUp(int val, int n) => (val + n - 1) & -n;
}
