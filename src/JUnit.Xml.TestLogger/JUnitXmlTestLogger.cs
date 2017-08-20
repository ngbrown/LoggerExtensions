namespace Microsoft.VisualStudio.TestPlatform.Extension.JUnit.Xml.TestLogger
{
    using System;
    using System.Collections.Concurrent;
    using System.Collections.Generic;
    using System.Globalization;
    using System.IO;
    using System.Linq;
    using System.Xml.Linq;
    using Microsoft.VisualStudio.TestPlatform.ObjectModel;
    using Microsoft.VisualStudio.TestPlatform.ObjectModel.Client;
    using Microsoft.VisualStudio.TestPlatform.ObjectModel.Logging;
    using System.Text;
    using System.Collections.ObjectModel;
    using System.Text.RegularExpressions;
    using System.Xml;

    /// <summary>
    /// 
    /// </summary>
    /// <remarks>
    /// Needs to look like: http://llg.cubic.org/docs/junit/
    /// minimal: https://stackoverflow.com/a/26661423/25182
    /// </remarks>
    [FriendlyName(FriendlyName)]
    [ExtensionUri(ExtensionUri)]
    public class JUnitXmlTestLogger : ITestLoggerWithParameters
    {
        /// <summary>
        /// Uri used to uniquely identify the logger.
        /// </summary>
        public const string ExtensionUri = "logger://Microsoft/TestPlatform/JUnitXmlLogger/v1";

        /// <summary>
        /// Alternate user friendly string to uniquely identify the console logger.
        /// </summary>
        public const string FriendlyName = "junit";

        public const string LogFilePathKey = "LogFilePath";
        public const string EnvironmentKey = "Environment";

        private string outputFilePath;
        private string environmentOpt;

        private ConcurrentBag<TestResultInfo> results;
        private DateTimeOffset localStartTime;

        private class TestResultInfo
        {
            public readonly TestCase TestCase;
            public readonly TestOutcome Outcome;
            public readonly string AssemblyName;
            private readonly string assemblyPath;
            public readonly string TypeName;
            public readonly string MethodName;
            public readonly string DisplayName;
            public readonly TimeSpan Duration;
            public readonly string ErrorMessage;
            public readonly string ErrorStackTrace;
            public readonly Collection<TestResultMessage> Messages;
            public readonly TraitCollection Traits;
            public readonly DateTimeOffset StartTime;

            public TestResultInfo(TestCase testCase, TestOutcome outcome, string assemblyName, string assemblyPath,
                string typeName, string methodName, string displayName, TimeSpan duration, string errorMessage,
                string errorStackTrace, Collection<TestResultMessage> messages, TraitCollection traits,
                DateTimeOffset startTime)
            {
                TestCase = testCase;
                Outcome = outcome;
                AssemblyName = assemblyName;
                this.assemblyPath = assemblyPath;
                TypeName = typeName;
                MethodName = methodName;
                DisplayName = displayName;
                Duration = duration;
                ErrorMessage = errorMessage;
                ErrorStackTrace = errorStackTrace;
                Messages = messages;
                Traits = traits;
                StartTime = startTime;
            }

            protected bool Equals(TestResultInfo other)
            {
                return string.Equals(TypeName, other.TypeName) && string.Equals(MethodName, other.MethodName) && string.Equals(DisplayName, other.DisplayName);
            }

            public override bool Equals(object obj)
            {
                if (ReferenceEquals(null, obj)) return false;
                if (ReferenceEquals(this, obj)) return true;
                if (obj.GetType() != this.GetType()) return false;
                return Equals((TestResultInfo) obj);
            }

            public override int GetHashCode()
            {
                unchecked
                {
                    var hashCode = (TypeName != null ? TypeName.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ (MethodName != null ? MethodName.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ (DisplayName != null ? DisplayName.GetHashCode() : 0);
                    return hashCode;
                }
            }
        }

        public void Initialize(TestLoggerEvents events, string testResultsDirPath)
        {
            if (events == null) throw new ArgumentNullException(nameof(events));
            if (testResultsDirPath == null) throw new ArgumentNullException(nameof(testResultsDirPath));

            var outputPath = Path.Combine(testResultsDirPath, "TestResults.xml");
            InitializeImpl(events, outputPath);
        }

        public void Initialize(TestLoggerEvents events, Dictionary<string, string> parameters)
        {
            if (events == null) throw new ArgumentNullException(nameof(events));
            if (parameters == null) throw new ArgumentNullException(nameof(parameters));

            if (parameters.TryGetValue(LogFilePathKey, out string outputPath))
            {
                InitializeImpl(events, outputPath);
            }
            else if (parameters.TryGetValue(DefaultLoggerParameterNames.TestRunDirectory, out string outputDir))
            {
                Initialize(events, outputDir);
            }
            else
            {
                throw new ArgumentException($"Expected {LogFilePathKey} or {DefaultLoggerParameterNames.TestRunDirectory} parameter", nameof(parameters));
            }

            parameters.TryGetValue(EnvironmentKey, out environmentOpt);
        }

        private void InitializeImpl(TestLoggerEvents events, string outputPath)
        {
            events.TestRunMessage += TestMessageHandler;
            events.TestResult += TestResultHandler;
            events.TestRunComplete += TestRunCompleteHandler;

            outputFilePath = Path.GetFullPath(outputPath);

            results = new ConcurrentBag<TestResultInfo>();

            localStartTime = DateTimeOffset.Now;
        }

        /// <summary>
        /// Called when a test message is received.
        /// </summary>
        internal void TestMessageHandler(object sender, TestRunMessageEventArgs e)
        {
        }

        /// <summary>
        /// Called when a test result is received.
        /// </summary>
        internal void TestResultHandler(object sender, TestResultEventArgs e)
        {
            TestResult result = e.Result;

            if (TryParseName(result.TestCase.FullyQualifiedName, out var typeName, out var methodName, out _))
            {
                var assemblyName = Path.GetFileNameWithoutExtension(result.TestCase.Source);

                results.Add(new TestResultInfo(
                    result.TestCase,
                    result.Outcome,
                    assemblyName,
                    result.TestCase.Source,
                    typeName,
                    methodName,
                    result.TestCase.DisplayName,
                    result.Duration,
                    result.ErrorMessage,
                    result.ErrorStackTrace,
                    result.Messages,
                    result.TestCase.Traits,
                    result.StartTime));
            }
        }

        /// <summary>
        /// Called when a test run is completed.
        /// </summary>
        internal void TestRunCompleteHandler(object sender, TestRunCompleteEventArgs e)
        {
            var resultList = results.ToList();
            results = new ConcurrentBag<TestResultInfo>();

            var doc = new XDocument(CreateTestsuitesElement(resultList))
            {
                Declaration = new XDeclaration("1.0", "utf-8", null)
            };

            // Create directory if not exist
            var loggerFileDirPath = Path.GetDirectoryName(outputFilePath);
            if (!Directory.Exists(loggerFileDirPath))
            {
                Directory.CreateDirectory(loggerFileDirPath);
            }

            using (var f = new StreamWriter(File.Create(outputFilePath), new UTF8Encoding(false, true)))
            {
                doc.Save(f);
            }
        }

        /// <summary>
        /// One per file, could contain results from multiple test assemblies
        /// </summary>
        private XElement CreateTestsuitesElement(IReadOnlyCollection<TestResultInfo> resultList)
        {
            var testsNumber = resultList.Count;

            var resultsByAssembly = from result in resultList
                group result by result.AssemblyName
                into byAssembly
                orderby byAssembly.Key
                select byAssembly;

            var testsuiteElements = resultsByAssembly.Select((infos, i) => CreateTestsuiteElement(i, infos.Key, infos.ToList()))
                .ToList();

            var element = new XElement("testsuites",
                new XAttribute("disabled", testsuiteElements.Sum(x => x.Disabled)),
                new XAttribute("errors", testsuiteElements.Sum(x => x.Errors)),
                new XAttribute("failures", testsuiteElements.Sum(x => x.Failures)),
                new XAttribute("tests", testsNumber),
                new XAttribute("time", testsuiteElements.Sum(x => x.TimeSeconds)),
                testsuiteElements.Select(x => x.Element)
            );

            return element;
        }

        /// <summary>
        /// Nested under <c>testsuites</c>, especially if there is more than one.
        /// </summary>
        /// <param name="id">Starts at 0 for the first testsuite and is incremented by 1 for each following testsuite</param>
        /// <param name="assemblyName"></param>
        /// <param name="testResultInfos"></param>
        private ElementWithCounts CreateTestsuiteElement(int id, string assemblyName, IReadOnlyCollection<TestResultInfo> testResultInfos)
        {
            var resultsByTypeName = from result in testResultInfos
                group result by result.TypeName
                into byTypeName
                orderby byTypeName.Key
                select byTypeName;

            // TODO: This is really already supposed to be a single type, and the contents the list of methods in it.
            var testcaseElements =
                resultsByTypeName.SelectMany(grouping => grouping.AsEnumerable(),
                    (grouping, infos) => CreateTestcaseElement(grouping.Key, infos))
                    .ToList();

            var totalTests = testcaseElements.Sum(x => x.TotalTests);
            var disabled = testcaseElements.Sum(x => x.Disabled);
            var errors = testcaseElements.Sum(x => x.Errors);
            var failures = testcaseElements.Sum(x => x.Failures);
            var skipped = testcaseElements.Sum(x => x.Skipped);

            var element = new XElement("testsuite",
                new XAttribute("name", assemblyName),
                new XAttribute("tests", totalTests),
                new XAttribute("disabled", disabled),
                new XAttribute("errors", errors),
                new XAttribute("failures", failures),
                new XAttribute("skipped", skipped),
                new XAttribute("id", id),
                new XAttribute("timestamp", localStartTime.ToString("O", CultureInfo.InvariantCulture)),
                testcaseElements.Select(x => x.Element));

            return new ElementWithCounts()
            {
                TotalTests = totalTests,
                Disabled = disabled,
                Errors = errors,
                Failures = failures,
                Skipped = skipped,
                Element = element,
            };
        }

        private ElementWithCounts CreateTestcaseElement(string typeName, TestResultInfo result)
        {
            var element = new XElement("testcase",
                new XAttribute("name", result.DisplayName),
                new XAttribute("classname", result.TypeName),
                new XAttribute("status", OutcomeToString(result.Outcome)),
                new XAttribute("time", result.Duration.TotalSeconds));

            string resultElementName = null;
            switch (result.Outcome)
            {
                case TestOutcome.Failed:
                    resultElementName = "failure";
                    break;
                case TestOutcome.Skipped:
                    resultElementName = "skipped";
                    break;
                case TestOutcome.NotFound:
                    resultElementName = "error";
                    break;
            }

            if (resultElementName != null)
            {
                var failureElement = new XElement(resultElementName);
                if (result.ErrorMessage != null)
                {
                    failureElement.Add(new XAttribute("message", result.ErrorMessage));
                }
                if (result.ErrorStackTrace != null)
                {
                    failureElement.Add(new XCData(result.ErrorStackTrace));
                }
                element.Add(failureElement);
            }

            var stdOut = new StringBuilder();
            foreach (var m in result.Messages)
            {
                if (string.Equals(TestResultMessage.StandardOutCategory, m.Category, StringComparison.OrdinalIgnoreCase))
                {
                    stdOut.AppendLine(m.Text);
                }
            }

            if (!string.IsNullOrWhiteSpace(stdOut.ToString()))
            {
                element.Add(new XElement("system-out", new XCData(stdOut.ToString())));
            }

            var errOut = new StringBuilder();
            foreach (var m in result.Messages)
            {
                if (string.Equals(TestResultMessage.StandardErrorCategory, m.Category, StringComparison.OrdinalIgnoreCase))
                {
                    errOut.AppendLine(m.Text);
                }
            }

            if (!string.IsNullOrWhiteSpace(errOut.ToString()))
            {
                element.Add(new XElement("system-err", new XCData(errOut.ToString())));
            }

            return new ElementWithCounts()
            {
                TotalTests = 1,
                Disabled = result.Outcome == TestOutcome.None ? 1 : 0,
                Errors = result.Outcome == TestOutcome.NotFound ? 1 : 0,
                Failures = result.Outcome == TestOutcome.Failed ? 1 : 0,
                Skipped = result.Outcome == TestOutcome.Skipped ? 1 : 0,
                Element = element,
            };
        }

        private static bool TryParseName(string testCaseName, out string metadataTypeName, out string metadataMethodName, out string metadataMethodArguments)
        {
            // This is fragile. The FQN is constructed by a test adapter. 
            // There is no enforcement that the FQN starts with metadata type name.

            string typeAndMethodName;
            var methodArgumentsStart = testCaseName.IndexOf('(');

            if (methodArgumentsStart == -1)
            {
                typeAndMethodName = testCaseName.Trim();
                metadataMethodArguments = string.Empty;
            }
            else
            {
                typeAndMethodName = testCaseName.Substring(0, methodArgumentsStart).Trim();
                metadataMethodArguments = testCaseName.Substring(methodArgumentsStart).Trim();

                if (metadataMethodArguments[metadataMethodArguments.Length - 1] != ')')
                {
                    metadataTypeName = null;
                    metadataMethodName = null;
                    metadataMethodArguments = null;
                    return false;
                }
            }

            var typeNameLength = typeAndMethodName.LastIndexOf('.');
            var methodNameStart = typeNameLength + 1;

            if (typeNameLength <= 0 || methodNameStart == typeAndMethodName.Length) // No typeName is available
            {
                metadataTypeName = null;
                metadataMethodName = null;
                metadataMethodArguments = null;
                return false;
            }

            metadataTypeName = typeAndMethodName.Substring(0, typeNameLength).Trim();
            metadataMethodName = typeAndMethodName.Substring(methodNameStart).Trim();
            return true;
        }

        private static string OutcomeToString(TestOutcome outcome)
        {
            switch (outcome)
            {
                case TestOutcome.Failed:
                    return "Fail";

                case TestOutcome.Passed:
                    return "Pass";

                case TestOutcome.Skipped:
                    return "Skipped";

                default:
                    return "Unknown";
            }
        }

        private static string RemoveInvalidXmlChar(string str)
        {
            if (str != null)
            {
                // From xml spec (http://www.w3.org/TR/xml/#charsets) valid chars: 
                // #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]  

                // we are handling only #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD]
                // because C# support unicode character in range \u0000 to \uFFFF
                MatchEvaluator evaluator = new MatchEvaluator(ReplaceInvalidCharacterWithUniCodeEscapeSequence);
                string invalidChar = @"[^\x09\x0A\x0D\x20-\uD7FF\uE000-\uFFFD]";
                return Regex.Replace(str, invalidChar, evaluator);
            }

            return str;
        }

        private static string ReplaceInvalidCharacterWithUniCodeEscapeSequence(Match match)
        {
            char x = match.Value[0];
            return string.Format(@"\u{0:x4}", (ushort)x);
        }
    }

    internal class ElementWithCounts
    {
        public XElement Element { get; set; }
        public int TotalTests { get; set; }
        public int Disabled { get; set; }
        public int Errors { get; set; }
        public int Failures { get; set; }
        public int Skipped { get; set; }
        public double TimeSeconds { get; set; }
    }
}

