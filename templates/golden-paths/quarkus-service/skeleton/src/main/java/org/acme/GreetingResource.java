package org.acme;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;

@Path("/api/v1")
public class GreetingResource {

    @GET
    @Path("/hello")
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, String> hello() {
        return Map.of(
            "service", "${{ values.component_id }}",
            "message", "Hello from Red Hat Developer Hub Golden Path Microservice!",
            "runtime", "Quarkus 3.x"
        );
    }
}
