"""Run the pure Kotlin classifier checks using the local Gradle compiler cache."""
from pathlib import Path
import subprocess
import tempfile

root = Path.home() / '.gradle/caches/modules-2/files-2.1'
def jar(group, name, version=None):
    folder = root / group / name
    return str(next((folder / version if version else folder).rglob('*.jar')))

stdlib = jar('org.jetbrains.kotlin', 'kotlin-stdlib', '1.8.22')
classpath = ':'.join([
    jar('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '1.8.22'),
    stdlib,
    jar('org.jetbrains.kotlin', 'kotlin-script-runtime', '1.8.22'),
    jar('org.jetbrains.kotlin', 'kotlin-reflect'),
    jar('org.jetbrains.intellij.deps', 'trove4j'),
    jar('org.jetbrains', 'annotations', '13.0'),
])
java = '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java'
with tempfile.TemporaryDirectory() as out:
    subprocess.run([java, '-cp', classpath, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                    '-no-stdlib', '-no-reflect', '-classpath', stdlib, '-d', out,
                    'android/app/src/main/kotlin/com/example/log_noti/BalanceClassifier.kt',
                    'test/native/BalanceClassifierTest.kt'], check=True)
    subprocess.run([java, '-cp', out + ':' + stdlib, 'BalanceClassifierTestKt'], check=True)
