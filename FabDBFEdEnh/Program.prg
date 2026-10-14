USING System
USING System.IO
USING System.IO.Pipes
USING System.Text
USING System.Threading
USING System.Collections.Generic
USING System.Linq
USING System.Windows.Forms

USING FabDBFEdEnh

BEGIN NAMESPACE FabDBFEdEnh

[STAThread] ;
	FUNCTION Start() AS VOID
    // Single instance: if the app is already running, the file is handed to the open window
    LOCAL cFile := "" AS STRING
    LOCAL aArgs := Environment.GetCommandLineArgs() AS STRING[]
    IF aArgs:Length > 1
        cFile := (STRING) aArgs:GetValue( 1 )            // GetValue is 0-based, 0 = exe
        TRY
            cFile := Path.GetFullPath( cFile )
        CATCH
            NOP
        END TRY
    ENDIF
    LOCAL lFirst := FALSE AS LOGIC
    LOCAL oMutex := Mutex{ TRUE, "FabDBFEdEnh_dBAdministrator_Single", OUT lFirst } AS Mutex
    IF ! lFirst
        IF SingleInstance.SendFile( cFile )
            RETURN
        ENDIF
        // running instance does not answer -> start normally
    ENDIF

    // No more silent termination on errors: log and report
    LOCAL oError := ErrorLog{} AS ErrorLog
    Application.SetUnhandledExceptionMode( UnhandledExceptionMode.CatchException )
    Application.ThreadException += ThreadExceptionEventHandler{ oError, @UiError() }
    AppDomain.CurrentDomain:UnhandledException += UnhandledExceptionEventHandler{ oError, @FatalError() }

    Application.EnableVisualStyles()
    Application.SetCompatibleTextRenderingDefault( FALSE )
    LOCAL oMain := MainForm{} AS MainForm
    LOCAL oReceiver  := SingleInstance{ oMain } AS SingleInstance
    oReceiver:StartListening()
    Application.Run( oMain )
    GC.KeepAlive( oMutex )
    RETURN


/// <summary>Writes unhandled errors to %APPDATA%\FabDBFEdEnh\Error.log</summary>
PUBLIC CLASS ErrorLog

    PUBLIC STATIC METHOD LogFile() AS STRING
        LOCAL cFolder := Path.Combine( Environment.GetFolderPath( Environment.SpecialFolder.ApplicationData ), "FabDBFEdEnh" ) AS STRING
        TRY
            IF ! Directory.Exists( cFolder )
                Directory.CreateDirectory( cFolder )
            ENDIF
        CATCH
            NOP
        END TRY
        RETURN Path.Combine( cFolder, "Error.log" )

    PUBLIC STATIC METHOD Write( cKind AS STRING, oEx AS OBJECT ) AS VOID
        IF AppSettings.Active != NULL .AND. ! AppSettings.Active:LogErrors
            RETURN                              // Set Defaults: "Set Error Log" switched off
        ENDIF
        TRY
            LOCAL cText := DateTime.Now:ToString( "dd.MM.yyyy HH:mm:ss" ) + "  " + cKind + Environment.NewLine + ;
                IIF( oEx == NULL, "(no details)", oEx:ToString() ) + Environment.NewLine + ;
                "------------------------------------------------------------" + Environment.NewLine AS STRING
            File.AppendAllText( LogFile(), cText )
        CATCH
            NOP
        END TRY
        RETURN

    // Error in the window thread: log it, report it, the app keeps running
    PUBLIC METHOD UiError( sender AS OBJECT, e AS ThreadExceptionEventArgs ) AS VOID
        Write( "Error (program continues)", e:Exception )
        TRY
            MessageBox.Show( "An error has occurred:" + Environment.NewLine + Environment.NewLine + ;
                e:Exception:Message + Environment.NewLine + Environment.NewLine + ;
                "Details are in " + LogFile(), "FabDBFEdEnh - Error", MessageBoxButtons.OK, MessageBoxIcon.Error )
        CATCH
            NOP
        END TRY
        RETURN

    // Error in another thread: the program is terminated by .NET -> at least log it
    PUBLIC METHOD FatalError( sender AS OBJECT, e AS UnhandledExceptionEventArgs ) AS VOID
        Write( "FATAL error (program will terminate)", e:ExceptionObject )
        TRY
            MessageBox.Show( "Fatal error - the program will terminate." + Environment.NewLine + ;
                "Details are in " + LogFile(), "FabDBFEdEnh - Error", MessageBoxButtons.OK, MessageBoxIcon.Stop )
        CATCH
            NOP
        END TRY
        RETURN

END CLASS


/// <summary>
/// Receives the file names of further program starts through a named pipe
/// (double click on a DBF while the app is already running).
/// </summary>
PUBLIC CLASS SingleInstance
    PRIVATE STATIC PIPENAME := "FabDBFEdEnh_dBAdministrator_Pipe" AS STRING
    PRIVATE oWindow AS MainForm

    PUBLIC CONSTRUCTOR( oF AS MainForm )
        SELF:oWindow := oF
        RETURN

    PUBLIC METHOD StartListening() AS VOID
        LOCAL oTextWindow := Thread{ ThreadStart{ SELF, @Listen() } } AS Thread
        oTextWindow:IsBackground := TRUE
        oTextWindow:Start()
        RETURN

    PRIVATE METHOD Listen() AS VOID
        DO WHILE TRUE
            LOCAL cFile := NULL AS STRING
            TRY
                LOCAL oS := NamedPipeServerStream{ PIPENAME, PipeDirection.In } AS NamedPipeServerStream
                TRY
                    oS:WaitForConnection()
                    LOCAL oR := StreamReader{ oS, Encoding.UTF8 } AS StreamReader
                    cFile := oR:ReadToEnd()
                FINALLY
                    oS:Dispose()
                END TRY
            CATCH
                Thread.Sleep( 500 )
            END TRY
            IF cFile != NULL .AND. SELF:oWindow != NULL .AND. SELF:oWindow:IsHandleCreated .AND. ! SELF:oWindow:IsDisposed
                TRY
                    SELF:oWindow:BeginInvoke( Action<STRING>{ SELF:oWindow, @OnExternalFile() }, <OBJECT>{ cFile } )
                CATCH
                    NOP
                END TRY
            ENDIF
        ENDDO

    /// <summary>Send the file name to the running instance. FALSE = no instance reachable.</summary>
    PUBLIC STATIC METHOD SendFile( cFile AS STRING ) AS LOGIC
        TRY
            LOCAL oCheck := NamedPipeClientStream{ ".", PIPENAME, PipeDirection.Out } AS NamedPipeClientStream
            TRY
                oCheck:Connect( 3000 )
                LOCAL aBlock := Encoding.UTF8:GetBytes( IIF( cFile == NULL, "", cFile ) ) AS BYTE[]
                oCheck:Write( aBlock, 0, aBlock:Length )
                oCheck:Flush()
            FINALLY
                oCheck:Dispose()
            END TRY
            RETURN TRUE
        CATCH
            RETURN FALSE
        END TRY

END CLASS

END NAMESPACE
