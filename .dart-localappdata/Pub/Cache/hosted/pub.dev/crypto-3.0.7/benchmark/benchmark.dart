// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show exit, stderr;
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  Hash? function;
  int? customSize;

  void setFunction(Hash newFunction, String message) {
    if (function != null) {
      stderr.writeln('Hash function already set.');
      exit(1);
    }
    function = newFunction;
    print('Using hash function $message');
  }

  for (var arg in args) {
    if (arg == 'md5') {
      setFunction(md5, 'md5');
    } else if (arg == 'sha1') {
      setFunction(sha1, 'sha1');
    } else if (arg == 'sha256') {
      setFunction(sha256, 'sha256');
    } else if (arg == 'sha224') {
      setFunction(sha224, 'sha224');
    } else if (arg == 'sha384') {
      setFunction(sha384, 'sha384');
    } else if (arg == 'sha512') {
      setFunction(sha512, 'sha512');
    } else if (arg == 'sha512224') {
      setFunction(sha512224, 'sha512/224');
    } else if (arg == 'sha512256') {
      setFunction(sha512256, 'sha512/256');
    } else if (arg.startsWith('--custom=')) {
      customSize = int.parse(arg.substring('--custom='.length));
    } else {
      stderr.writeln('Unknown argument: $arg');
      exit(1);
    }
  }
  if (function == null) {
    setFunction(md5, 'md5');
  }

  if (customSize != null) {
    doIterationsChunk(function!, mb: customSize, iterations: 1, doPrint: true);
    return;
  }

  // Warmup.
  doIterationsChunk(function!, mb: 1, iterations: 100, doPrint: false);

  // Benchmarks.
  print('One chunk input');
  doIterationsChunk(function!, mb: 1, iterations: 1000, doPrint: true);
  doIterationsChunk(function!, mb: 10, iterations: 100, doPrint: true);
  doIterationsChunk(function!, mb: 100, iterations: 10, doPrint: true);
  doIterationsChunk(function!, mb: 1000, iterations: 1, doPrint: true);

  print('');
  print('Add in 1024 byte chunks:');
  doIterationsSmallChunks(function!,
      chunkSize: 1024, mb: 1, iterations: 1000, doPrint: true);

  print('');
  print('Add in 100 byte chunks:');
  doIterationsSmallChunks(function!,
      chunkSize: 100, mb: 1, iterations: 1000, doPrint: true);

  print('');
  print('Add in 4 byte chunks:');
  doIterationsSmallChunks(function!,
      chunkSize: 4, mb: 1, iterations: 1000, doPrint: true);
}

void doIterationsChunk(Hash function,
    {required int mb, required int iterations, required bool doPrint}) {
  var data = Uint8List(1024 * 1024 * mb);
  var runtimesInMs = <double>[];
  for (var i = 0; i < iterations; i++) {
    runtimesInMs.add(hashChunk(data, function));
  }
  if (doPrint) {
    printStats(runtimesInMs, data.length, iterations);
  }
}

void doIterationsSmallChunks(Hash function,
    {required int chunkSize,
    required int mb,
    required int iterations,
    required bool doPrint}) {
  var data = Uint8List(chunkSize);
  var runtimesInMs = <double>[];
  var addIterations = mb * 1024 * 1024 ~/ chunkSize;
  for (var i = 0; i < iterations; i++) {
    runtimesInMs.add(hashSmallChunks(data, addIterations, function));
  }
  if (doPrint) {
    printStats(runtimesInMs, data.length * addIterations, iterations);
  }
}

double hashChunk(Uint8List data, Hash function) {
  var stopwatch = Stopwatch()..start();
  var hash = function.convert(data);
  stopwatch.stop();
  if (hash.bytes.isEmpty) throw StateError('This should never happen');
  return stopwatch.elapsedMicroseconds / 1000;
}

double hashSmallChunks(Uint8List data, int addTimes, Hash function) {
  var stopwatch = Stopwatch()..start();

  var output = AccumulatorSink<Digest>();
  var input = function.startChunkedConversion(output);
  for (var i = 0; i < addTimes; i++) {
    input.add(data);
  }

  input.close();
  var hash = output.events.single;

  stopwatch.stop();
  if (hash.bytes.isEmpty) throw StateError('This should never happen');
  return stopwatch.elapsedMicroseconds / 1000;
}

void printStats(List<double> runtimesInMs, int dataLength, int iterations) {
  var mb = dataLength / 1024 / 1024;
  runtimesInMs.sort();
  var sum = runtimesInMs.reduce((value, element) => value + element);
  var averageRuntimeInMs = sum / runtimesInMs.length;
  var averageKbPerMs = dataLength / 1024 / averageRuntimeInMs;
  var medianRuntimeInMs = runtimesInMs[runtimesInMs.length ~/ 2];
  var medianKbPerMs = dataLength / 1024 / medianRuntimeInMs;
  print(
      'Processed ${mb.toStringAsFixed(2)} mb of data with an average/median of '
      '${averageKbPerMs.toStringAsFixed(2)} / '
      '${medianKbPerMs.toStringAsFixed(2)} '
      'kb per ms.');
}
