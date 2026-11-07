FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline
COPY src ./src
RUN mvn -B -ntp package -DskipTests

FROM eclipse-temurin:21-jre
RUN useradd --system --uid 10001 guardian
WORKDIR /app
COPY --from=build /app/target/guardian-backend-0.1.0-SNAPSHOT.jar /app/guardian.jar
USER guardian
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/guardian.jar"]