FROM flink:1.12.1-scala_2.11

# Copy sql-client script
COPY sql-client/ /opt/sql-client
RUN mkdir -p /opt/sql-client/lib

# Download connector libraries
RUN wget -P /opt/sql-client/lib/ https://repo.maven.apache.org/maven2/org/apache/flink/flink-json/1.12.1/flink-json-1.12.1.jar; \
  # wget -P /opt/sql-client/lib/ https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka_2.11/1.12.1/flink-sql-connector-kafka_2.11-1.12.1.jar; \
  # wget -P /opt/sql-client/lib/ https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-elasticsearch7_2.11/1.12.1/flink-sql-connector-elasticsearch7_2.11-1.12.1.jar; \
  wget -P /opt/sql-client/lib/ https://repo.maven.apache.org/maven2/org/apache/flink/flink-connector-jdbc_2.11/1.12.1/flink-connector-jdbc_2.11-1.12.1.jar; \
  wget -P /opt/sql-client/lib/ https://repo1.maven.org/maven2/com/alibaba/ververica/flink-sql-connector-postgres-cdc/1.2.0/flink-sql-connector-postgres-cdc-1.2.0.jar; \
  wget -P /opt/sql-client/lib/ https://repo.maven.apache.org/maven2/org/postgresql/postgresql/42.2.14/postgresql-42.2.14.jar;

# Copy configuration
COPY conf/* /opt/flink/conf/

WORKDIR /opt/sql-client
ENV SQL_CLIENT_HOME /opt/sql-client

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
