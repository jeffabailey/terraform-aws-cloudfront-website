    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri === "/.well-known/atproto-did") {
        return {
          statusCode: 200,
          statusDescription: "OK",
          headers: {
            "content-type": { value: "text/plain" }
          },
          body: "did:plc:iavkd7iqcdeawn2u7uj3rekb"
        };
      }

      return request;
    }
