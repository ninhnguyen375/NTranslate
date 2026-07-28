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
    private readonly AppConfig _originalConfig;
    private readonly string _originalApiKey;
    private readonly Func<SettingsSaveRequest, CancellationToken, Task> _save;
    private readonly Action _requestClose;
    private readonly ISettingsFolderPicker? _folderPicker;
    private string? _errorMessage;

    public SettingsViewModel(
        AppConfig config,
        string apiKey,
        Func<SettingsSaveRequest, CancellationToken, Task> save,
        Action requestClose,
        ISettingsFolderPicker? folderPicker = null)
    {
        _originalConfig = config;
        _originalApiKey = apiKey;
        _save = save;
        _requestClose = requestClose;
        _folderPicker = folderPicker;
        Draft = SettingsDraft.From(config, apiKey);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public SettingsDraft Draft { get; }
    public string? ErrorMessage
    {
        get => _errorMessage;
        private set { _errorMessage = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ErrorMessage))); }
    }

    public void Revert()
    {
        Draft.Revert(_originalConfig, _originalApiKey);
        ErrorMessage = null;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Draft)));
    }

    public void Cancel() => _requestClose();

    public async Task BrowseHistoryDirectoryAsync(CancellationToken token)
    {
        if (_folderPicker is null) return;
        var path = await _folderPicker.PickAsync(_folderPicker.OwnerHwnd, token).ConfigureAwait(false);
        if (path is null) return;
        Draft.HistoryDirectory = path;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Draft)));
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
            await _save(new(config, Draft.ApiKey, Draft.SpeechRate, Draft.StartWithWindows), token).ConfigureAwait(false);
            ErrorMessage = null;
            _requestClose();
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            ErrorMessage = exception.Message;
        }
    }
}
