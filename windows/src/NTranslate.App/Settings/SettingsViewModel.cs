using System.ComponentModel;
using System.Runtime.CompilerServices;
using NTranslate.Core.Configuration;
using NTranslate.Core.Settings;

namespace NTranslate.App.Settings;

public interface ISettingsFolderPicker
{
    nint OwnerHwnd { get; }
    Task<string?> PickAsync(nint ownerHwnd, CancellationToken token);
}

public sealed record SettingsSaveRequest(AppConfig Config, string ApiKey, double SpeechRate, bool StartWithWindows);

public sealed class SettingsViewModel : INotifyPropertyChanged
{
    private AppConfig _originalConfig;
    private string _originalApiKey;
    private readonly Func<SettingsSaveRequest, CancellationToken, Task> _save;
    private readonly Func<CancellationToken, Task<(AppConfig Config, string ApiKey)>>? _refresh;
    private readonly Action _requestClose;
    private ISettingsFolderPicker? _folderPicker;
    private string? _errorMessage;

    public SettingsViewModel(
        AppConfig config,
        string apiKey,
        Func<SettingsSaveRequest, CancellationToken, Task> save,
        Action requestClose,
        ISettingsFolderPicker? folderPicker = null,
        Func<CancellationToken, Task<(AppConfig Config, string ApiKey)>>? refresh = null)
    {
        _originalConfig = config;
        _originalApiKey = apiKey;
        _save = save;
        _requestClose = requestClose;
        _folderPicker = folderPicker;
        _refresh = refresh;
        Draft = SettingsDraft.From(config, apiKey);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public SettingsDraft Draft { get; }
    public string NewLanguage { get; set; } = string.Empty;
    public string NewTargetLanguage { get; set; } = string.Empty;
    public string? ErrorMessage
    {
        get => _errorMessage;
        private set
        {
            if (_errorMessage == value) return;
            _errorMessage = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ErrorMessage)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(HasError)));
        }
    }
    public bool HasError => !string.IsNullOrWhiteSpace(ErrorMessage);

    public void Revert()
    {
        Draft.Revert(_originalConfig, _originalApiKey);
        ErrorMessage = null;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Draft)));
    }

    public void Cancel() => _requestClose();

    public async Task RefreshAsync(CancellationToken token)
    {
        if (_refresh is null) return;
        var snapshot = await _refresh(token).ConfigureAwait(false);
        _originalConfig = snapshot.Config;
        _originalApiKey = snapshot.ApiKey;
        Draft.Revert(_originalConfig, _originalApiKey);
        ErrorMessage = null;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Draft)));
    }

    public void AddLanguage() => Add(NewLanguage, Draft.Languages);
    public void RemoveLanguage(string language) => Remove(language, Draft.Languages);
    public void AddTargetLanguage() => Add(NewTargetLanguage, Draft.TargetLanguages);
    public void RemoveTargetLanguage(string language) => Remove(language, Draft.TargetLanguages);

    internal void SetFolderPicker(ISettingsFolderPicker folderPicker) => _folderPicker = folderPicker;

    public async Task BrowseHistoryDirectoryAsync(CancellationToken token)
    {
        if (_folderPicker is null) return;
        try
        {
            var path = await _folderPicker.PickAsync(_folderPicker.OwnerHwnd, token);
            if (path is null) return;
            Draft.HistoryDirectory = path;
            ErrorMessage = null;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Draft)));
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            ErrorMessage = $"Could not select history folder: {exception.Message}";
        }
    }

    public async Task SaveAsync(CancellationToken token)
    {
        var issues = Draft.Validate();
        if (issues.Count != 0)
        {
            ErrorMessage = string.Join(Environment.NewLine, issues.Select(issue => $"{issue.Field}: {issue.Message}"));
            return;
        }

        try
        {
            var config = Draft.ToAppConfig(_originalConfig);
            if (ConfigEquals(_originalConfig, config) && string.Equals(_originalApiKey, Draft.ApiKey, StringComparison.Ordinal))
            {
                ErrorMessage = null;
                _requestClose();
                return;
            }

            await _save(new(config, Draft.ApiKey, Draft.SpeechRate, Draft.StartWithWindows), token);
            _originalConfig = config;
            _originalApiKey = Draft.ApiKey;
            Draft.Revert(_originalConfig, _originalApiKey);
            ErrorMessage = null;
            _requestClose();
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            ErrorMessage = FormatError(exception);
        }
    }

    internal void ReportError(Exception exception) => ErrorMessage = FormatError(exception);

    private static string FormatError(Exception exception)
    {
        if (exception is not SettingsCommitException commit) return exception.Message;
        var message = commit.PrimaryException.Message;
        return commit.RollbackExceptions.Count == 0
            ? message
            : $"{message}{Environment.NewLine}Rollback failed: {string.Join("; ", commit.RollbackExceptions.Select(error => error.Message))}";
    }

    private static bool ConfigEquals(AppConfig left, AppConfig right) =>
        left.Languages.SequenceEqual(right.Languages, StringComparer.Ordinal) &&
        left.TargetLanguages.SequenceEqual(right.TargetLanguages, StringComparer.Ordinal) &&
        left with { Languages = right.Languages, TargetLanguages = right.TargetLanguages } == right;

    private void Add(string value, List<string> values)
    {
        value = value.Trim();
        if (value.Length == 0 || values.Contains(value, StringComparer.OrdinalIgnoreCase)) return;
        values.Add(value);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Draft)));
    }

    private void Remove(string value, List<string> values)
    {
        var match = values.FirstOrDefault(item => string.Equals(item, value, StringComparison.OrdinalIgnoreCase));
        if (match is null) return;
        values.Remove(match);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Draft)));
    }
}
