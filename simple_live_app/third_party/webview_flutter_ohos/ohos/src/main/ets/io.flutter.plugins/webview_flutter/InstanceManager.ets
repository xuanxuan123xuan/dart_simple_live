// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on InstanceManager.java originally written by
// Copyright 2013 The Flutter Authors.

import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

export class InstanceManager {
  private MIN_HOST_CREATED_IDENTIFIER = 65536;

  private CLEAR_FINALIZED_WEAK_REFERENCES_INTERVAL = 3000;

  private TAG = "InstanceManager";

  private finalizationListener: FinalizationListener;

  private identifiers: WeakMap<ESObject, number> = new WeakMap<ESObject, number>();

  private Instances: Map<number, ESObject> = new Map<number, ESObject>();

  private firstIdentifier: number = 0;

  private nextIdentifier: number = this.MIN_HOST_CREATED_IDENTIFIER;

  private releaseTimer: ESObject = null;

  private hasFinalizationListenerStopped: boolean = false;

  public create<T>(finalizationListener: FinalizationListener): InstanceManager {
    return new InstanceManager(finalizationListener);
  }

  public fHasFinalizationListenerStopped(): boolean {
    return this.hasFinalizationListenerStopped;
  }

  constructor(finalizationListener: FinalizationListener) {
    this.finalizationListener = finalizationListener;
    this.releaseTimer = setTimeout(() => {
      this.releaseAllFinalizedInstances()
    }, this.CLEAR_FINALIZED_WEAK_REFERENCES_INTERVAL)
  }

  public remove(identifier: number): ESObject | null {
    this.logWarningIfFinalizationListenerHasStopped();

    return this.Instances.delete(identifier) as ESObject | null;
  }

  getInstance(identifier: number): ESObject {
    this.logWarningIfFinalizationListenerHasStopped();
    return this.Instances.get(identifier);
  }

  clear() {
    this.Instances.clear();
    this.identifiers = new WeakMap<ESObject, number>();
  }

  private releaseAllFinalizedInstances(): void {
    if (this.fHasFinalizationListenerStopped()) {
      return;
    }
    // this.Instances.clear();
    // this.identifiers.clear()
    // this.finalizationListener.onFinalize(this.firstIdentifier)
    this.releaseTimer = setTimeout(() => {
      this.releaseAllFinalizedInstances()
    }, this.CLEAR_FINALIZED_WEAK_REFERENCES_INTERVAL)
  }

  stopFinalizationListener() {
    if (this.releaseTimer) {
      clearTimeout(this.releaseTimer);
    }
    this.hasFinalizationListenerStopped = true;
  }


  private addInstance(instance: ESObject, identifier: number) {
    if (identifier < 0) {
      throw Error(`Identifier must be >= 0: ${identifier}`);
    }
    if (this.Instances.has(identifier)) {
      throw new Error(`Identifier has already been added: ${identifier}`);
    }
    if (this.Instances.size === 0) {
      this.firstIdentifier = identifier
    }

    this.identifiers.set(instance, identifier);
    this.Instances.set(identifier, instance);
  }

  getIdentifier(instance: Object): number {
    this.logWarningIfFinalizationListenerHasStopped();
    const identifier: number = this.identifiers.get(instance) ?? -1;
    return identifier;
  }

  private logWarningIfFinalizationListenerHasStopped() {
    if (this.fHasFinalizationListenerStopped()) {
      Log.w(this.TAG, "The manager was used after calls to the FinalizationListener have been stopped.");
    }
  }

  public containsInstance(instance: ESObject): boolean {
    this.logWarningIfFinalizationListenerHasStopped();
    return this.identifiers.has(instance);
  }

  public addHostCreatedInstance(instance: ESObject): number {
    this.logWarningIfFinalizationListenerHasStopped();

    if (this.containsInstance(instance)) {
      throw new Error(
        `Instance of ${instance.constructor.name} has already been added.`);
    }
    const identifier = this.nextIdentifier++;
    this.addInstance(instance, identifier);
    return identifier;
  }

  addDartCreatedInstance(instance: ESObject, identifier: number) {
    this.logWarningIfFinalizationListenerHasStopped();
    this.addInstance(instance, identifier);
  }
}

interface FinalizationListener {
  onFinalize: (identifier: number) => void;
}