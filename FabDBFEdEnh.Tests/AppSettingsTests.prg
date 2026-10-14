USING System
USING Xunit

BEGIN NAMESPACE FabDBFEd.Tests

PUBLIC CLASS AppSettingsTests

    [Fact];
    PUBLIC METHOD NetPattern_ConvertsVoFormat() AS VOID
        Assert.Equal( "dd.MM.yyyy", AppSettings.NetPattern( "DD.MM.YYYY" ) )
        Assert.Equal( "yy'/'MM'/'dd", AppSettings.NetPattern( "YY/MM/DD" ) )
        RETURN

    [Fact];
    PUBLIC METHOD DateText_EmptyDateIsEmptyString() AS VOID
        Assert.Equal( "", AppSettings.DateText( DateTime.MinValue ) )
        RETURN

    [Fact];
    PUBLIC METHOD ParseDate_AcceptsDefaultAndCompactFormats() AS VOID
        Assert.Equal( DateTime{ 2026, 10, 14 }, AppSettings.ParseDate( "14.10.2026" ) )
        Assert.Equal( DateTime{ 2026, 10, 14 }, AppSettings.ParseDate( "20261014" ) )
        RETURN

END CLASS

END NAMESPACE
