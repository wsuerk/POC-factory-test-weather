package com.example.weather.web;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Hello-world endpoint for the Weather API skeleton. */
@RestController
public class HelloController {

	static final String GREETING = "Hello from Weather";

	@GetMapping("/api/hello")
	public String hello() {
		return GREETING;
	}

}
