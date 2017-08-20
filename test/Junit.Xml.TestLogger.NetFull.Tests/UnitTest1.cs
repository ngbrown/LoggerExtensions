using System;
using Xunit;
using Xunit.Abstractions;

namespace Junit.Xml.TestLogger.NetFull.Tests
{
    public class UnitTest1
    {
        [Fact]
        public void PassTest11()
        {
        }

        [Fact]
        public void FailTest11()
        {
            Assert.False(true);
        }

        [Fact(Skip = "Reason for skipping test")]
        public void SkipTest13()
        {
            Assert.Equal(2, 2);
        }
    }

    public class UnitTest2
    {
        [Fact]
        public void PAssTest21()
        {
            Assert.Equal(2, 2);
        }

        [Fact]
        public void FailTest22()
        {
            Assert.False(true);
        }

        [Theory]
        [InlineData(1)]
        [InlineData(2)]
        [InlineData(3)]
        [InlineData("four")]
        public void TheoryDataTest23(object value)
        {
            Assert.IsType<int>(value);
        }
    }

    public class UnitTest3
    {
        private readonly ITestOutputHelper output;

        public UnitTest3(ITestOutputHelper output)
        {
            this.output = output;
        }

        [Fact]
        public void PAssTest31()
        {
            output.WriteLine("Some standard text output.");
            Assert.Equal(2, 2);
        }

        [Fact]
        public void FailTest32()
        {
            output.WriteLine("Some standard text output.");
            Assert.False(true);
        }
    }
}
