const React = require("react");

function areDepsEqual(previousDeps, nextDeps) {
  if (!previousDeps || !nextDeps || previousDeps.length !== nextDeps.length) {
    return false;
  }

  for (let index = 0; index < previousDeps.length; index += 1) {
    if (!Object.is(previousDeps[index], nextDeps[index])) {
      return false;
    }
  }

  return true;
}

function useHostResource(factory, deps = [], options = {}) {
  const { initialData } = options;
  const [state, setState] = React.useState({
    data: initialData,
    isLoading: true,
    error: undefined,
  });
  const controllerRef = React.useRef(null);
  const factoryRef = React.useRef(factory);
  const depsRef = React.useRef();

  factoryRef.current = factory;

  const refresh = React.useCallback(() => {
    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;

    setState((currentState) => ({
      data: currentState.data,
      isLoading: true,
      error: undefined,
    }));

    Promise.resolve()
      .then(() => factoryRef.current(controller.signal))
      .then((data) => {
        if (controller.signal.aborted || controllerRef.current !== controller) {
          return;
        }

        setState({
          data,
          isLoading: false,
          error: undefined,
        });
      })
      .catch((error) => {
        if (controller.signal.aborted || controllerRef.current !== controller) {
          return;
        }

        if (error?.name === "AbortError") {
          return;
        }

        setState((currentState) => ({
          data: currentState.data,
          isLoading: false,
          error,
        }));
      });
  }, []);

  React.useEffect(() => {
    const depsChanged = !areDepsEqual(depsRef.current, deps);
    depsRef.current = deps;
    if (!depsChanged) {
      return;
    }

    refresh();
  });

  React.useEffect(() => {
    return () => {
      controllerRef.current?.abort();
    };
  }, []);

  return {
    data: state.data,
    isLoading: state.isLoading,
    error: state.error,
    refresh,
  };
}

function useHostMutation(handler) {
  const [state, setState] = React.useState({
    isPending: false,
    error: undefined,
  });
  const handlerRef = React.useRef(handler);
  const mutationIDRef = React.useRef(0);

  handlerRef.current = handler;

  const mutate = React.useCallback(async (input) => {
    const mutationID = mutationIDRef.current + 1;
    mutationIDRef.current = mutationID;
    setState({
      isPending: true,
      error: undefined,
    });

    try {
      const result = await handlerRef.current(input);
      if (mutationIDRef.current === mutationID) {
        setState({
          isPending: false,
          error: undefined,
        });
      }
      return result;
    } catch (error) {
      if (mutationIDRef.current === mutationID) {
        setState({
          isPending: false,
          error,
        });
      }
      throw error;
    }
  }, []);

  const clearError = React.useCallback(() => {
    setState((currentState) => {
      if (currentState.error === undefined) {
        return currentState;
      }

      return {
        ...currentState,
        error: undefined,
      };
    });
  }, []);

  return {
    mutate,
    isPending: state.isPending,
    error: state.error,
    clearError,
  };
}

function useHostSubscriptionResource(options) {
  const {
    initialData,
    load,
    subscribe,
    normalize = (value) => value,
    onResolved,
  } = options;
  const [state, setState] = React.useState({
    data: initialData,
    isLoading: true,
    error: undefined,
  });
  const loadRef = React.useRef(load);
  const subscribeRef = React.useRef(subscribe);
  const normalizeRef = React.useRef(normalize);
  const onResolvedRef = React.useRef(onResolved);
  const requestIdRef = React.useRef(0);
  const revisionRef = React.useRef(0);

  loadRef.current = load;
  subscribeRef.current = subscribe;
  normalizeRef.current = normalize;
  onResolvedRef.current = onResolved;

  const applyResolvedData = React.useCallback((value) => {
    const nextData = normalizeRef.current(value);
    revisionRef.current += 1;
    setState({
      data: nextData,
      isLoading: false,
      error: undefined,
    });
    onResolvedRef.current?.(nextData);
    return nextData;
  }, []);

  const clearError = React.useCallback(() => {
    setState((currentState) => {
      if (currentState.error === undefined) {
        return currentState;
      }

      return {
        ...currentState,
        error: undefined,
      };
    });
  }, []);

  const refresh = React.useCallback(() => {
    const requestId = requestIdRef.current + 1;
    requestIdRef.current = requestId;
    const revisionAtStart = revisionRef.current;

    setState((currentState) => ({
      data: currentState.data,
      isLoading: true,
      error: undefined,
    }));

    Promise.resolve()
      .then(() => loadRef.current())
      .then((data) => {
        if (requestIdRef.current !== requestId) {
          return;
        }

        if (revisionRef.current !== revisionAtStart) {
          setState((currentState) => ({
            data: currentState.data,
            isLoading: false,
            error: undefined,
          }));
          return;
        }

        applyResolvedData(data);
      })
      .catch((error) => {
        if (requestIdRef.current !== requestId) {
          return;
        }

        if (revisionRef.current !== revisionAtStart) {
          setState((currentState) => ({
            data: currentState.data,
            isLoading: false,
            error: undefined,
          }));
          return;
        }

        setState((currentState) => ({
          data: currentState.data,
          isLoading: false,
          error,
        }));
      });
  }, [applyResolvedData]);

  React.useEffect(() => {
    const subscribeFn = subscribeRef.current;
    if (typeof subscribeFn !== "function") {
      return () => {
        requestIdRef.current += 1;
        revisionRef.current += 1;
      };
    }

    const unsubscribe = subscribeFn((value) => {
      applyResolvedData(value);
    });

    return () => {
      requestIdRef.current += 1;
      revisionRef.current += 1;
      unsubscribe?.();
    };
  }, [applyResolvedData]);

  React.useEffect(() => {
    refresh();
  }, [refresh]);

  return {
    data: state.data,
    isLoading: state.isLoading,
    error: state.error,
    refresh,
    clearError,
  };
}

function useHostValue({ externalValue, write }) {
  const [state, setState] = React.useState({
    hasOptimisticValue: false,
    optimisticValue: externalValue,
  });
  const externalValueRef = React.useRef(externalValue);
  const previousExternalValueRef = React.useRef(externalValue);
  const stateRef = React.useRef(state);
  const mutation = useHostMutation(write);

  externalValueRef.current = externalValue;
  stateRef.current = state;

  const externalDidChange = !Object.is(previousExternalValueRef.current, externalValue);
  const value = state.hasOptimisticValue && !externalDidChange
    ? state.optimisticValue
    : externalValue;

  React.useEffect(() => {
    if (!externalDidChange) {
      return;
    }

    previousExternalValueRef.current = externalValue;
    setState({
      hasOptimisticValue: false,
      optimisticValue: externalValue,
    });
    mutation.clearError();
  }, [externalDidChange, externalValue, mutation.clearError]);

  const setValue = React.useCallback((nextValue) => {
    const currentState = stateRef.current;
    const baseValue = currentState.hasOptimisticValue
      ? currentState.optimisticValue
      : externalValueRef.current;
    const resolvedValue = typeof nextValue === "function"
      ? nextValue(baseValue)
      : nextValue;

    setState({
      hasOptimisticValue: true,
      optimisticValue: resolvedValue,
    });

    mutation.mutate(resolvedValue).catch(() => {
      setState({
        hasOptimisticValue: false,
        optimisticValue: externalValueRef.current,
      });
    });
  }, [mutation.mutate]);

  return {
    value,
    setValue,
    isPending: mutation.isPending,
    error: mutation.error,
  };
}

module.exports = {
  useHostSubscriptionResource,
  useHostResource,
  useHostMutation,
  useHostValue,
};
