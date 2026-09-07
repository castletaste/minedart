{{flutter_js}}
{{flutter_build_config}}

(() => {
  const loader = window.minedartLoader;
  let failureReported = false;

  const reportFailure = (error) => {
    if (failureReported) return;
    failureReported = true;
    console.error('Minedart engine startup failed.', error);
    loader.fail();
  };

  _flutter.loader
    .load({
      serviceWorkerSettings: {
        serviceWorkerVersion: {{flutter_service_worker_version}},
      },
      onEntrypointLoaded: async (engineInitializer) => {
        try {
          const appRunner = await engineInitializer.initializeEngine();
          await appRunner.runApp();
          loader.complete();
        } catch (error) {
          reportFailure(error);
        }
      },
    })
    .catch(reportFailure);
})();
