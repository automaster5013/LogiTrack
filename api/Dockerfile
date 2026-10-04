FROM maven:3-eclipse-temurin-24@sha256:a137a467ec89b5713d0be817b55bdba6b4d6ef16e3d05565a79bc08d8e775a1c AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline
COPY src src
RUN mvn -q package
FROM eclipse-temurin:21-jre-alpine@sha256:1a29e1fe337eb28b5bec30f0ee8ed29f0ff80ab6f75dcf9313efe82911065a52
RUN addgroup -S app && adduser -S app -G app
USER app
COPY --from=build /app/target/control-api-0.1.0.jar /app.jar
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=6 \
  CMD wget -qO- http://127.0.0.1:8080/actuator/health/readiness | grep UP || exit 1
ENTRYPOINT ["java","-jar","/app.jar"]
