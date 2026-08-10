[default]
run:
    mvn compile exec:java -Dexec.mainClass="io.github.wormt.CoplandMon.Application"

clean:
    mvn clean

build:
    mvn clean package -DskipTests
