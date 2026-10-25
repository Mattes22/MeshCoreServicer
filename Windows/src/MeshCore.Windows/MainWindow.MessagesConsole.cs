using System;
using System.Linq;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using MeshCore.Core;

namespace MeshCore.Windows;
public sealed partial class MainWindow
{
    private UIElement MessagesPage()
    {
        var search = UI.Input("", 130); search.ToolTip = "Hledat konverzace"; search.Margin = new(10); var scope = new TabControl { Margin = new(10, 0, 10, 8) };
        foreach (var name in new[] { "Vše", "Soukromé", "Kanály" }) scope.Items.Add(new TabItem { Header = name, Padding = new(9, 5, 9, 5) }); scope.SelectedIndex = 0;
        var conversations = new ListBox(); var thread = new StackPanel { Margin = new(20) }; ScrollViewer scroll = new() { Content = thread, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        var threadTitle = UI.Text("Vyberte konverzaci", 15); threadTitle.FontWeight = FontWeights.SemiBold; var threadDetail = UI.Secondary("Soukromé konverzace a kanály vašeho companionu", 11);
        var muted = UI.Check("Ztišit"); var compose = UI.Input("", 100); compose.AcceptsReturn = true; compose.TextWrapping = TextWrapping.Wrap; compose.Height = 78; compose.MaxLength = 133; compose.Margin = new(0, 0, 0, 8);
        var count = UI.Secondary("0/133 UTF-8 B", 11); count.FontFamily = UI.Mono; var emptyThread = UI.Empty("messages", "Vyberte konverzaci", "Kanály se načtou z companionu. Soukromou zprávu lze poslat uloženému companion kontaktu."); thread.Children.Add(emptyThread);
        string? renderedConversation = null; string? current = model.Conversation; bool updating = false; string rendered = "", renderedConversations = ""; string? account = model.Archive?.Account;
        compose.Text = current == null ? "" : drafts.GetValueOrDefault(current, "");
        int Limit() => model.Channels.Any(c => c.Id == current && c.Configured) ? Math.Max(0, Math.Min(133, 160 - Encoding.UTF8.GetByteCount(model.Self?.Name ?? "") - 2)) : 133;
        bool CanSend() => Local && current != null && !string.IsNullOrWhiteSpace(compose.Text) && Encoding.UTF8.GetByteCount(compose.Text) <= Limit();
        void Count() { count.Text = $"{Encoding.UTF8.GetByteCount(compose.Text)}/{Limit()} UTF-8 B · Ctrl+Enter odešle"; }
        async Task Send() { var text = compose.Text; await model.SendMessage(text); if (model.Error == null && compose.Text == text) { compose.Clear(); if (current != null) drafts.Remove(current); } }
        var send = UI.Primary(UI.WithIcon(Action("Odeslat", Send, CanSend), "send"));
        compose.TextChanged += (_, _) => { if (current != null && !updating) drafts[current] = compose.Text; Count(); send.IsEnabled = CanSend(); };
        compose.PreviewKeyDown += async (_, e) => { if (e.Key == Key.Enter && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { e.Handled = true; if (CanSend()) await Invoke(Send); } };
        conversations.SelectionChanged += (_, _) => { if (!updating && (conversations.SelectedItem as ListBoxItem)?.Tag is string id) { current = id; model.SelectConversation(id); compose.Text = drafts.GetValueOrDefault(id, ""); rendered = ""; } };
        muted.Click += async (_, _) => await Invoke(() => model.Mute(muted.IsChecked == true));
        void Render()
        {
            updating = true;
            try
            {
                if (account != model.Archive?.Account) { account = model.Archive?.Account; compose.Clear(); current = null; renderedConversations = rendered = ""; }
                if (current != model.Conversation) { current = model.Conversation; compose.Text = current == null ? "" : drafts.GetValueOrDefault(current, ""); rendered = ""; }
                var items = model.Conversations.Where(c => c.Title.Contains(search.Text, StringComparison.OrdinalIgnoreCase) && (scope.SelectedIndex == 0 || c.Id.StartsWith(scope.SelectedIndex == 2 ? "channel:" : "dm:", StringComparison.Ordinal))).ToArray();
                string conversationSignature = string.Join('|', items.Select(c => c.Id + c.Title)) + model.Archive?.Messages.Count + model.Unread + current;
                if (conversationSignature != renderedConversations)
                {
                    renderedConversations = conversationSignature; conversations.Items.Clear();
                    foreach (var item in items)
                    {
                        var history = (model.Archive?.Messages ?? []).Where(m => m.Conversation == item.Id).ToArray(); var last = history.LastOrDefault(); var unread = history.Count(m => !m.Outgoing && !m.Seen);
                        var name = UI.Text(item.Title, 13); name.FontWeight = FontWeights.SemiBold; var preview = UI.Secondary(last?.Text ?? "Zatím žádné zprávy", 11); preview.TextWrapping = TextWrapping.NoWrap; preview.TextTrimming = TextTrimming.CharacterEllipsis;
                        var meta = UI.Secondary(unread > 0 ? $"{unread} nepřečtených" : last?.Date.LocalDateTime.ToString("g") ?? "", 10); var text = UI.Stack(name, preview, meta);
                        DockPanel line = new() { Margin = new(0, 4, 0, 4) }; line.Children.Add(item.Id.StartsWith("channel:", StringComparison.Ordinal) ? UI.Avatar("hash", 34) : UI.NodeAvatar(1, 34)); line.Children.Add(text);
                        var row = new ListBoxItem { Content = line, Tag = item.Id }; conversations.Items.Add(row); if (item.Id == current) conversations.SelectedItem = row;
                    }
                    if (items.Length == 0) conversations.Items.Add(new ListBoxItem { Content = UI.Secondary("Žádné konverzace. Načtěte kanály a kontakty nebo upravte filtr."), IsHitTestVisible = false });
                }
                threadTitle.Text = model.Conversations.FirstOrDefault(c => c.Id == current).Title ?? "Vyberte konverzaci";
                threadDetail.Text = current == null ? "Historie tohoto companionu" : current.StartsWith("channel:", StringComparison.Ordinal) ? "Skupinový kanál · bez potvrzení doručení" : "Soukromé zprávy · doručení potvrzuje ACK protějšku";
                muted.IsChecked = model.Muted; muted.IsEnabled = current != null;
                var messages = model.Messages.ToArray(); var signature = current + string.Join('|', messages.Select(m => m.Id + m.Display + m.Captures.LastOrDefault()?.Date.ToString("O")));
                if (signature != rendered)
                {
                    bool stickToEnd = renderedConversation != current || scroll.ScrollableHeight - scroll.VerticalOffset < 24; renderedConversation = current; rendered = signature;
                    var expanded = thread.Children.OfType<Border>().Where(b => b.Tag is Guid && b.Child is StackPanel panel && panel.Children.OfType<Expander>().Any(e => e.IsExpanded)).Select(b => (Guid)b.Tag).ToHashSet(); thread.Children.Clear();
                    if (messages.Length == 0) thread.Children.Add(UI.Empty("messages", current == null ? "Vyberte konverzaci" : "Zatím žádné zprávy", "Přijaté zprávy se průběžně načítají z fronty companionu."));
                    foreach (var message in messages) { var bubble = MessageBubble(message); if (expanded.Contains(message.Id) && bubble.Child is StackPanel panel) foreach (var detail in panel.Children.OfType<Expander>()) detail.IsExpanded = true; thread.Children.Add(bubble); }
                    if (stickToEnd) _ = Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(scroll.ScrollToEnd));
                }
                compose.IsEnabled = Local && current != null; Count();
            }
            finally { updating = false; }
        }
        search.TextChanged += (_, _) => { renderedConversations = ""; Render(); }; scope.SelectionChanged += (_, _) => { renderedConversations = ""; Render(); }; refreshPage = Render;
        var top = UI.Heading("Komunikace přes companion", "Zprávy", "Soukromé konverzace a kanály vaší MeshCore sítě.", UI.WithIcon(Action("Přijmout zprávy", () => model.RefreshMessages(), () => Local), "down"));
        DockPanel left = new(); DockPanel.SetDock(search, Dock.Top); left.Children.Add(search); DockPanel.SetDock(scope, Dock.Top); left.Children.Add(scope); var archiveNote = UI.Secondary("Historie tohoto companionu", 10); archiveNote.Margin = new(15); DockPanel.SetDock(archiveNote, Dock.Bottom); left.Children.Add(archiveNote); left.Children.Add(conversations);
        DockPanel right = new(); var threadHead = UI.Columns(UI.Stack(threadTitle, threadDetail), muted); threadHead.Margin = new(20, 18, 20, 12); DockPanel.SetDock(threadHead, Dock.Top); right.Children.Add(threadHead);
        DockPanel composerFooter = new(); DockPanel.SetDock(send, Dock.Right); composerFooter.Children.Add(send); composerFooter.Children.Add(count);
        var composer = UI.Stack(compose, composerFooter); var composerBox = new Border { Child = composer, Padding = new(16), BorderThickness = new(0, 1, 0, 0) }; composerBox.SetResourceReference(Border.BorderBrushProperty, "AppBorder"); DockPanel.SetDock(composerBox, Dock.Bottom); right.Children.Add(composerBox); right.Children.Add(scroll);
        var leftBorder = new Border { Child = left, BorderThickness = new(0, 0, 1, 1) }; leftBorder.SetResourceReference(Border.BorderBrushProperty, "AppBorder");
        var split = new ResponsiveSplit(leftBorder, right, 300, 820, 280); var container = UI.Card(split, 0); container.Margin = new(0);

        DockPanel page = new(); DockPanel.SetDock(top, Dock.Top); page.Children.Add(top); page.Children.Add(container); return page;
    }
    private static Border MessageBubble(ChatRecord message)
    {
        var speaker = UI.Text(message.Outgoing ? "Vy" : message.Sender, 11); speaker.FontWeight = FontWeights.SemiBold; if (message.Outgoing) speaker.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
        var date = UI.Secondary(message.Date.LocalDateTime.ToString("g"), 10); date.TextAlignment = TextAlignment.Right;
        var text = UI.ReadText(message.Text, double.NaN); text.BorderThickness = new(0); text.Background = Brushes.Transparent; text.Padding = new(0); text.Margin = new(0, 3, 0, 12); text.FontSize = 16;
        var content = UI.Stack(UI.Columns(speaker, date), text, UI.Secondary((message.Outgoing ? "↑  " : "↙  ") + message.Delivery, 11));
        if (message.Hops.HasValue || message.Forwardings.HasValue) content.Children.Add(UI.Columns(UI.Secondary(message.Hops.HasValue ? $"{message.Hops} přeposlání v cestě" : "Cesta neznámá", 11), UI.Secondary(message.Forwardings.HasValue ? $"Zachyceno {message.Forwardings} přeposlání" : "Přeposlání nezjištěna", 11)));
        if (message.Captures.Count > 0) { var captures = UI.ReadText(string.Join('\n', message.Captures.Select(c => c.Display)), Math.Min(180, 25 + message.Captures.Count * 24)); captures.FontFamily = UI.Mono; captures.FontSize = 12; content.Children.Add(new Expander { Header = $"Zachycené kopie · posledních {message.Captures.Count}", Content = captures, Margin = new(0, 6, 0, 10), FontSize = 13 }); }
        if (message.Snr.HasValue) content.Children.Add(UI.Secondary($"Přijatá zpráva na companionu · SNR {message.Snr:F2} dB", 10));
        var card = UI.Card(content, 16); card.Tag = message.Id; card.MaxWidth = 720; card.MinWidth = 220; card.HorizontalAlignment = message.Outgoing ? HorizontalAlignment.Right : HorizontalAlignment.Left; card.Margin = new(message.Outgoing ? 44 : 0, 0, message.Outgoing ? 0 : 44, 18); if (message.Outgoing) card.SetResourceReference(Border.BackgroundProperty, "Selection"); return card;
    }
    private UIElement ConsolePage()
    {
        var input = UI.Input("", 100); input.FontFamily = UI.Mono; input.FontSize = 15; input.Margin = new(0); input.Padding = new(10, 12, 10, 12);
        var suggestions = new ListBox { MaxHeight = 130 }; var help = UI.Secondary(""); var support = UI.Secondary("", 11); var syntax = UI.Text("", 13); syntax.FontFamily = UI.Mono;
        var filter = UI.Input("", 180); filter.ToolTip = "Hledat v příkazech a odpovědích"; var terminalTitle = UI.Text("Repeater / LoRa", 12); terminalTitle.FontFamily = UI.Mono;
        var lines = new RichTextBox { IsReadOnly = true, IsUndoEnabled = false, BorderThickness = new(0), Background = Brushes.Transparent, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, FontFamily = UI.Mono, FontSize = 15, Padding = new(0), Document = new FlowDocument { PagePadding = new(18) } }; lines.SetResourceReference(Control.ForegroundProperty, "TerminalText");
        var nodes = UI.Combo(model.Contacts.Where(c => c.Kind == 2).ToArray(), 190); nodes.SelectedItem = model.Node; bool updating = false; string? consoleAccount = model.Archive?.Account, consoleNode = model.SelectedNode; int historyIndex = -1; string commandDraft = "", renderSignature = "";
        void Accept(string value) { input.Text = value; input.CaretIndex = value.Length; input.Focus(); }
        var inputBytes = UI.Secondary("0/133 B", 10); inputBytes.FontFamily = UI.Mono;
        void Complete()
        {
            suggestions.ItemsSource = model.Options.Suggestions ? Commands.Suggest(input.Text, model.History, model.Options.SuggestWrites, model.Options.History).ToArray() : Array.Empty<string>(); suggestions.Visibility = model.Options.Suggestions ? Visibility.Visible : Visibility.Collapsed;
            var entry = Commands.Entry(input.Text); help.Visibility = syntax.Visibility = support.Visibility = model.Options.Help ? Visibility.Visible : Visibility.Collapsed; syntax.Text = entry?.Syntax ?? "Příkazy vzdáleného repeateru";
            help.Text = entry == null ? "Pište příkaz nebo český název. Tab vloží návrh, ↑/↓ změní výběr, Esc zavře návrhy. Ctrl+↑/↓ prochází bezpečnou historii." : entry.Title + "\n" + entry.Detail;
            support.Text = entry == null ? "Katalog v1.18 · podpora závisí na firmwaru uzlu." : model.Support(input.Text); inputBytes.Text = $"{Encoding.UTF8.GetByteCount(input.Text)}/133 B";
        }
        async Task Send() { var text = input.Text; await model.SendCli(text); if ((model.Error == null || Commands.Sensitive(text)) && input.Text == text) input.Clear(); historyIndex = -1; Complete(); }
        input.TextChanged += (_, _) => Complete();
        input.PreviewKeyDown += async (_, e) =>
        {
            if (e.Key == Key.Escape) { suggestions.ItemsSource = Array.Empty<string>(); e.Handled = true; }
            else if (e.Key == Key.Tab && suggestions.Items.Count > 0) { Accept((suggestions.SelectedItem ?? suggestions.Items[0]).ToString()!); e.Handled = true; }
            else if (e.Key is Key.Up or Key.Down)
            {
                e.Handled = true;
                if (suggestions.Items.Count > 0 && !Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) suggestions.SelectedIndex = Math.Clamp(suggestions.SelectedIndex + (e.Key == Key.Up ? -1 : 1), 0, suggestions.Items.Count - 1);
                else if (model.Options.History && model.History.Count > 0) { if (historyIndex < 0) commandDraft = input.Text; historyIndex = Math.Clamp(historyIndex + (e.Key == Key.Up ? 1 : -1), -1, model.History.Count - 1); Accept(historyIndex < 0 ? commandDraft : model.History[historyIndex]); }
            }
            else if (e.Key == Key.Enter && (model.Options.EnterSends || Keyboard.Modifiers.HasFlag(ModifierKeys.Control))) { e.Handled = true; if (Admin) await Invoke(Send); }
        };
        suggestions.MouseDoubleClick += (_, _) => { if (suggestions.SelectedItem is string text) Accept(text); };
        nodes.SelectionChanged += async (_, _) => { if (!updating && nodes.SelectedItem is Contact c) await Invoke(async () => { await model.SelectNode(c.Id); }); };
        async Task Catalog()
        {
            var choice = UI.Combo(Commands.Catalog, 400); var description = UI.Secondary("Vyberte příkaz. Vložení nic neodesílá."); choice.SelectionChanged += (_, _) => { if (choice.SelectedItem is CatalogEntry c) description.Text = c.Title + "\n" + c.Detail; };
            Dialog dialog = new(this, "Katalog příkazů", UI.Stack(choice, description), "Vložit"); dialog.Setup(); if (dialog.ShowDialog() == true && choice.SelectedItem is CatalogEntry entry) Accept(entry.Command + (entry.Arguments.Length > 0 ? " " : "")); await Task.CompletedTask;
        }
        async Task Shortcuts()
        {
            var choice = UI.Combo(model.Library.Shortcuts.Where(s => s.Account == model.Archive?.Account).ToArray(), 400);
            Dialog dialog = new(this, "Oblíbené příkazy a šablony", UI.Stack(choice, UI.Secondary("Uloží se pouze typ příkazu; hodnoty zadáte při použití."), UI.Row(UI.Button("Uložit aktuální typ", () => Invoke(async () => { if (Commands.Entry(input.Text) is not { } entry) throw new MeshException("Vyberte příkaz z katalogu."); if (Dialog.Prompt(this, "Nová zkratka", "Název zkratky", entry.Title) is { } title) { await model.AddShortcut(title, entry.Command); UI.Source(choice, model.Library.Shortcuts.Where(s => s.Account == model.Archive?.Account).ToArray()); } })), UI.Button("Odstranit", () => Invoke(async () => { if (choice.SelectedItem is Shortcut shortcut) { await model.DeleteShortcut(shortcut); UI.Source(choice, model.Library.Shortcuts.Where(s => s.Account == model.Archive?.Account).ToArray()); } })))), "Vyplnit"); dialog.Setup();
            if (dialog.ShowDialog() == true && choice.SelectedItem is Shortcut selected) { var entry = Commands.Entry(selected.Command)!; var argument = entry.Arguments.Length > 0 ? Dialog.Prompt(this, selected.Title, entry.Syntax) : ""; if (argument != null) Accept(selected.Fill(argument)); }
            await Task.CompletedTask;
        }
        void Render()
        {
            updating = true;
            try
            {
                if (consoleAccount != model.Archive?.Account || consoleNode != model.SelectedNode) { consoleAccount = model.Archive?.Account; consoleNode = model.SelectedNode; input.Clear(); commandDraft = ""; historyIndex = -1; }
                UI.Source(nodes, model.Contacts.Where(c => c.Kind == 2).ToArray()); nodes.SelectedItem = model.Node; nodes.IsEnabled = !model.Busy; terminalTitle.Text = (model.Node?.Name ?? "Žádný repeater") + "  /  LoRa";
                var entries = model.Console.Where(l => l.Node == model.SelectedNode && (l.Command + l.Response).Contains(filter.Text, StringComparison.OrdinalIgnoreCase)).ToArray(); var signature = string.Join('|', entries.Select(l => l.Date.ToString("O") + l.Command + l.Response + l.State));
                if (signature != renderSignature)
                {
                    renderSignature = signature; lines.Document.Blocks.Clear();
                    foreach (var entry in entries)
                    {
                        var heading = new Paragraph(new Run($"{entry.Date.LocalDateTime:T}  {model.Node?.Name}   ·   {entry.State}") { Foreground = (Brush)Application.Current.Resources["TerminalSecondary"] }) { Margin = new(0, 0, 0, 10), FontSize = 13 };
                        var command = new Paragraph(new Run("› " + entry.Command) { Foreground = (Brush)Application.Current.Resources["TerminalAccent"] }) { Margin = new(0, 0, 0, 8), FontSize = 16 };
                        var reply = new Paragraph(new Run(entry.Response) { Foreground = (Brush)Application.Current.Resources["TerminalText"] }) { Margin = new(0, 0, 0, 24) }; lines.Document.Blocks.Add(heading); lines.Document.Blocks.Add(command); lines.Document.Blocks.Add(reply);
                    }
                    if (entries.Length == 0) lines.Document.Blocks.Add(new Paragraph(new Run("Připraveno. Přihlaste správce a zadejte příkaz.\nOdpovědi repeateru se zobrazí tady.") { Foreground = (Brush)Application.Current.Resources["TerminalSecondary"] }));
                    lines.ScrollToEnd();
                }
                support.Text = Commands.Entry(input.Text) == null ? "Katalog v1.18 · podpora závisí na firmwaru uzlu." : model.Support(input.Text);
            }
            finally { updating = false; }
        }
        filter.TextChanged += (_, _) => Render(); refreshPage = Render;
        var quick = UI.Row(UI.Eyebrow("Vložit příkaz")); foreach (var (title, command) in new[] { ("Firmware", "ver"), ("Hardware", "board"), ("Název", "get name"), ("Rádio", "get radio"), ("Hodiny", "clock") }) quick.Children.Add(UI.Button(title, () => { Accept(command); return Task.CompletedTask; }));
        var send = UI.Primary(UI.WithIcon(Action("Odeslat", Send, () => Admin && !string.IsNullOrWhiteSpace(input.Text)), "send"));
        var actions = UI.Row(Action("Katalog", Catalog), Action("Oblíbené", Shortcuts), Action("Nastavení", () => { navigation.SelectedIndex = 6; return Task.CompletedTask; }), send); actions.VerticalAlignment = VerticalAlignment.Center; actions.Margin = new(12, 0, 0, 0);
        // Input always receives the full width; buttons wrap below it at larger text sizes.
        var commandLine = UI.Stack(input, UI.Row(inputBytes, actions)); inputBytes.VerticalAlignment = VerticalAlignment.Center; inputBytes.Margin = new(0, 8, 12, 0);

        var commandCard = UI.Card(commandLine, 12); commandCard.Margin = new(0, 12, 0, 10);
        var hints = UI.Columns(UI.Stack(UI.Eyebrow("Doplnit · Tab vloží návrh"), suggestions), UI.Stack(syntax, help, support)); hints.Margin = new(10, 16, 10, 8);
        var privacy = UI.Secondary("Tab doplnit · ↑↓ návrhy · Esc zavřít · Ctrl+Enter odeslat. Citlivé příkazy a odpovědi jsou skryté v historii.", 10);
        DockPanel terminal = new(); var terminalHead = new Border { Child = terminalTitle, Padding = new(16, 12, 16, 12), CornerRadius = new(12, 12, 0, 0) }; terminalHead.SetResourceReference(Border.BackgroundProperty, "TerminalHeader"); terminalTitle.SetResourceReference(TextBlock.ForegroundProperty, "TerminalText"); terminalTitle.Margin = new(0); DockPanel.SetDock(terminalHead, Dock.Top); terminal.Children.Add(terminalHead); terminal.Children.Add(lines); var terminalCard = new Border { Child = terminal, CornerRadius = new(12), MinHeight = 150 }; terminalCard.SetResourceReference(Border.BackgroundProperty, "TerminalBackground");
        DockPanel page = new(); var heading = UI.Heading("Přímý přístup k repeateru", "Vzdálená konzole", "CLI příkazy a skutečné odpovědi, přehledně v jedné relaci.", nodes); DockPanel.SetDock(heading, Dock.Top); page.Children.Add(heading); DockPanel.SetDock(quick, Dock.Top); page.Children.Add(quick);
        var searchRow = UI.Columns(UI.Stack(UI.Secondary("Hledat v příkazech a odpovědích…"), filter), Action("Vymazat výpis", () => { model.Console.Clear(); return Task.CompletedTask; }, () => !model.Busy)); DockPanel.SetDock(searchRow, Dock.Top); page.Children.Add(searchRow);
        var bottom = UI.Stack(hints, commandCard, privacy); DockPanel.SetDock(bottom, Dock.Bottom); page.Children.Add(bottom); page.Children.Add(terminalCard); Complete(); return page;
    }
}
