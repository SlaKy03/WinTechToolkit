# Palette (Catppuccin Mocha / Latte) e stili WPF dell'interfaccia.

$script:Themes = @{
    Dark  = [ordered]@{
        BgBrush = '#1E1E2E'; PanelBrush = '#181825'; CardBrush = '#313244'; CardHoverBrush = '#45475A'; LineBrush = '#45475A'
        TextBrush = '#CDD6F4'; SubtleBrush = '#A6ADC8'; AccentBrush = '#CBA6F7'; AccentHoverBrush = '#B4BEFE'; AccentSoftBrush = '#463E5E'
        OnAccentBrush = '#11111B'; KnobBrush = '#CDD6F4'; InputBrush = '#181825'; GridAltBrush = '#2A2B3D'; GridHeaderBrush = '#181825'
        SelectionBrush = '#585B70'; ScrollThumbBrush = '#585B70'; OkBrush = '#A6E3A1'; WarnBrush = '#F9E2AF'; ErrBrush = '#F38BA8'
        ErrHoverBrush = '#EBA0AC'; LogBgBrush = '#11111B'; BannerBrush = '#F9E2AF'; BannerTextBrush = '#11111B'; OverlayBrush = '#B311111B'
    }
    Light = [ordered]@{
        BgBrush = '#EFF1F5'; PanelBrush = '#E6E9EF'; CardBrush = '#FFFFFF'; CardHoverBrush = '#E6E9EF'; LineBrush = '#CCD0DA'
        TextBrush = '#4C4F69'; SubtleBrush = '#6C6F85'; AccentBrush = '#8839EF'; AccentHoverBrush = '#7A2FD6'; AccentSoftBrush = '#ECE2FD'
        OnAccentBrush = '#FFFFFF'; KnobBrush = '#FFFFFF'; InputBrush = '#FFFFFF'; GridAltBrush = '#F5F6F9'; GridHeaderBrush = '#E6E9EF'
        SelectionBrush = '#DCCBFA'; ScrollThumbBrush = '#ACB0BE'; OkBrush = '#40A02B'; WarnBrush = '#B7791F'; ErrBrush = '#D20F39'
        ErrHoverBrush = '#B00C30'; LogBgBrush = '#F4F5F8'; BannerBrush = '#F9E2AF'; BannerTextBrush = '#4C4F69'; OverlayBrush = '#804C4F69'
    }
}

function Get-WTBrushXaml([string]$Theme) {
    $t = $script:Themes[$Theme]
    $items = foreach ($k in $t.Keys) { '<SolidColorBrush x:Key="{0}" Color="{1}"/>' -f $k, $t[$k] }
    # corner between the scroll bars and other parts of the standard controls
    $items += '<SolidColorBrush x:Key="{{x:Static SystemColors.ControlBrushKey}}" Color="{0}"/>' -f $t.CardBrush
    $items -join ''
}

function Get-WTStyleXaml {
@'
<Style x:Key="ThinThumb" TargetType="Thumb">
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Thumb">
    <Border CornerRadius="4" Background="{DynamicResource ScrollThumbBrush}"/>
  </ControlTemplate></Setter.Value></Setter>
</Style>
<Style x:Key="PageButton" TargetType="RepeatButton">
  <Setter Property="Focusable" Value="False"/>
  <Setter Property="IsTabStop" Value="False"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType="ScrollBar">
  <Setter Property="Width" Value="10"/>
  <Setter Property="MinWidth" Value="10"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
    <Grid Background="Transparent">
      <Track x:Name="PART_Track" IsDirectionReversed="True">
        <Track.DecreaseRepeatButton><RepeatButton Style="{StaticResource PageButton}" Command="ScrollBar.PageUpCommand"/></Track.DecreaseRepeatButton>
        <Track.Thumb><Thumb Style="{StaticResource ThinThumb}" Margin="2"/></Track.Thumb>
        <Track.IncreaseRepeatButton><RepeatButton Style="{StaticResource PageButton}" Command="ScrollBar.PageDownCommand"/></Track.IncreaseRepeatButton>
      </Track>
    </Grid>
  </ControlTemplate></Setter.Value></Setter>
  <Style.Triggers>
    <Trigger Property="Orientation" Value="Horizontal">
      <Setter Property="Width" Value="Auto"/>
      <Setter Property="MinWidth" Value="0"/>
      <Setter Property="Height" Value="10"/>
      <Setter Property="MinHeight" Value="10"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
        <Grid Background="Transparent">
          <Track x:Name="PART_Track" IsDirectionReversed="False">
            <Track.DecreaseRepeatButton><RepeatButton Style="{StaticResource PageButton}" Command="ScrollBar.PageLeftCommand"/></Track.DecreaseRepeatButton>
            <Track.Thumb><Thumb Style="{StaticResource ThinThumb}" Margin="2"/></Track.Thumb>
            <Track.IncreaseRepeatButton><RepeatButton Style="{StaticResource PageButton}" Command="ScrollBar.PageRightCommand"/></Track.IncreaseRepeatButton>
          </Track>
        </Grid>
      </ControlTemplate></Setter.Value></Setter>
    </Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="Pill" TargetType="Button">
  <Setter Property="Background" Value="{DynamicResource CardBrush}"/>
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="12,6"/>
  <Setter Property="Margin" Value="0,0,6,6"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="HorizontalContentAlignment" Value="Center"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
      <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
      <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.8"/></Trigger>
      <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter Property="Background" Value="{DynamicResource CardHoverBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
    </Trigger>
  </Style.Triggers>
</Style>
<Style TargetType="Button" BasedOn="{StaticResource Pill}"/>
<Style x:Key="PillPrimary" TargetType="Button" BasedOn="{StaticResource Pill}">
  <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
  <Setter Property="Foreground" Value="{DynamicResource OnAccentBrush}"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter Property="Background" Value="{DynamicResource AccentHoverBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource AccentHoverBrush}"/>
    </Trigger>
  </Style.Triggers>
</Style>
<Style x:Key="PillDanger" TargetType="Button" BasedOn="{StaticResource Pill}">
  <Setter Property="Background" Value="{DynamicResource ErrBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource ErrBrush}"/>
  <Setter Property="Foreground" Value="{DynamicResource OnAccentBrush}"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter Property="Background" Value="{DynamicResource ErrHoverBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource ErrHoverBrush}"/>
    </Trigger>
  </Style.Triggers>
</Style>
<Style x:Key="Tile" TargetType="Button">
  <Setter Property="Background" Value="{DynamicResource CardBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="Width" Value="268"/>
  <Setter Property="MinHeight" Value="66"/>
  <Setter Property="Margin" Value="0,0,10,10"/>
  <Setter Property="Padding" Value="12,10"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
      <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
      <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.8"/></Trigger>
      <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter Property="Background" Value="{DynamicResource CardHoverBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
    </Trigger>
  </Style.Triggers>
</Style>
<Style x:Key="CaptionButton" TargetType="Button">
  <Setter Property="Width" Value="46"/>
  <Setter Property="Height" Value="48"/>
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
  <Setter Property="FontSize" Value="11"/>
  <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border Background="{TemplateBinding Background}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
  </ControlTemplate></Setter.Value></Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource CardHoverBrush}"/></Trigger>
  </Style.Triggers>
</Style>
<Style x:Key="CloseButton" TargetType="Button" BasedOn="{StaticResource CaptionButton}">
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter Property="Background" Value="#E81123"/>
      <Setter Property="Foreground" Value="White"/>
    </Trigger>
  </Style.Triggers>
</Style>
<Style x:Key="IconButton" TargetType="Button" BasedOn="{StaticResource CaptionButton}">
  <Setter Property="Width" Value="32"/>
  <Setter Property="Height" Value="26"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="Cursor" Value="Hand"/>
</Style>
<Style x:Key="LinkButton" TargetType="Button">
  <Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <ContentPresenter VerticalAlignment="Center"/>
  </ControlTemplate></Setter.Value></Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="NavButton" TargetType="RadioButton">
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="GroupName" Value="Nav"/>
  <Setter Property="Height" Value="38"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
    <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Margin="8,1">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="3"/><ColumnDefinition Width="41"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border x:Name="Bar" Background="{DynamicResource AccentBrush}" CornerRadius="1.5" Margin="0,9" Visibility="Hidden"/>
        <TextBlock x:Name="Icon" Grid.Column="1" Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" FontFamily="Segoe MDL2 Assets"
                   FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        <ContentPresenter Grid.Column="2" VerticalAlignment="Center"/>
      </Grid>
    </Border>
    <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource CardHoverBrush}"/></Trigger>
      <Trigger Property="IsChecked" Value="True">
        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentSoftBrush}"/>
        <Setter TargetName="Bar" Property="Visibility" Value="Visible"/>
        <Setter TargetName="Icon" Property="Foreground" Value="{DynamicResource AccentBrush}"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
      </Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
</Style>
<Style x:Key="NavHeader" TargetType="TextBlock">
  <Setter Property="FontSize" Value="10.5"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
  <Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/>
  <Setter Property="Margin" Value="22,14,0,5"/>
</Style>
<Style x:Key="Chip" TargetType="RadioButton">
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="Margin" Value="0,0,6,6"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
    <Border x:Name="Bd" CornerRadius="13" Padding="12,4" BorderThickness="1" BorderBrush="{DynamicResource LineBrush}" Background="{DynamicResource CardBrush}">
      <ContentPresenter HorizontalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/></Trigger>
      <Trigger Property="IsChecked" Value="True">
        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentBrush}"/>
        <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
        <Setter Property="Foreground" Value="{DynamicResource OnAccentBrush}"/>
      </Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
</Style>

<Style TargetType="CheckBox">
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="Margin" Value="6,4"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="VerticalAlignment" Value="Center"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
    <StackPanel Orientation="Horizontal" Background="Transparent">
      <Border x:Name="Box" Width="18" Height="18" CornerRadius="4" BorderThickness="1.5" BorderBrush="{DynamicResource SubtleBrush}" Background="Transparent" VerticalAlignment="Center">
        <Path x:Name="Mark" Data="M 3 8 L 6.5 11.5 L 13 4" Stroke="{DynamicResource OnAccentBrush}" StrokeThickness="2" Visibility="Collapsed"/>
      </Border>
      <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>
    <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/></Trigger>
      <Trigger Property="IsChecked" Value="True">
        <Setter TargetName="Box" Property="Background" Value="{DynamicResource AccentBrush}"/>
        <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
        <Setter TargetName="Mark" Property="Visibility" Value="Visible"/>
      </Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
</Style>
<Style x:Key="Switch" TargetType="CheckBox">
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="Margin" Value="8,4"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="VerticalAlignment" Value="Center"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
    <StackPanel Orientation="Horizontal" Background="Transparent">
      <Border x:Name="Track" Width="36" Height="19" CornerRadius="9.5" Background="{DynamicResource LineBrush}" VerticalAlignment="Center">
        <Ellipse x:Name="Knob" Width="13" Height="13" Fill="{DynamicResource KnobBrush}" HorizontalAlignment="Left" Margin="3,0"/>
      </Border>
      <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>
    <ControlTemplate.Triggers>
      <Trigger Property="IsChecked" Value="True">
        <Setter TargetName="Track" Property="Background" Value="{DynamicResource AccentBrush}"/>
        <Setter TargetName="Knob" Property="Fill" Value="{DynamicResource OnAccentBrush}"/>
        <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
      </Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
</Style>

<Style TargetType="TextBox">
  <Setter Property="Background" Value="{DynamicResource InputBrush}"/>
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
  <Setter Property="CaretBrush" Value="{DynamicResource TextBrush}"/>
  <Setter Property="SelectionBrush" Value="{DynamicResource AccentBrush}"/>
  <Setter Property="Padding" Value="6,4"/>
  <Setter Property="Margin" Value="0,0,6,6"/>
  <Setter Property="VerticalContentAlignment" Value="Center"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">
    <Border x:Name="Bd" CornerRadius="6" BorderThickness="1" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
      <ScrollViewer x:Name="PART_ContentHost" Focusable="False" Margin="{TemplateBinding Padding}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
    </Border>
    <ControlTemplate.Triggers>
      <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/></Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
</Style>
<Style x:Key="SearchBox" TargetType="TextBox" BasedOn="{StaticResource {x:Type TextBox}}">
  <Setter Property="Padding" Value="28,5,6,5"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">
    <Border x:Name="Bd" CornerRadius="6" BorderThickness="1" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
      <Grid>
        <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource SubtleBrush}" Margin="9,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        <TextBlock x:Name="Ph" Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" Foreground="{DynamicResource SubtleBrush}"
                   Margin="31,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" IsHitTestVisible="False"/>
        <ScrollViewer x:Name="PART_ContentHost" Focusable="False" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
      </Grid>
    </Border>
    <ControlTemplate.Triggers>
      <Trigger Property="Text" Value=""><Setter TargetName="Ph" Property="Visibility" Value="Visible"/></Trigger>
      <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/></Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
</Style>
<Style x:Key="CodeBox" TargetType="TextBox" BasedOn="{StaticResource {x:Type TextBox}}">
  <Setter Property="FontFamily" Value="Consolas"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="IsReadOnly" Value="True"/>
  <Setter Property="Margin" Value="0"/>
  <Setter Property="Padding" Value="8"/>
  <Setter Property="VerticalContentAlignment" Value="Stretch"/>
  <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
  <Setter Property="HorizontalScrollBarVisibility" Value="Auto"/>
</Style>

<Style TargetType="DataGrid">
  <Setter Property="AutoGenerateColumns" Value="False"/>
  <Setter Property="IsReadOnly" Value="True"/>
  <Setter Property="CanUserAddRows" Value="False"/>
  <Setter Property="CanUserResizeRows" Value="False"/>
  <Setter Property="SelectionMode" Value="Extended"/>
  <Setter Property="SelectionUnit" Value="FullRow"/>
  <Setter Property="HeadersVisibility" Value="Column"/>
  <Setter Property="GridLinesVisibility" Value="Horizontal"/>
  <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource LineBrush}"/>
  <Setter Property="Background" Value="{DynamicResource CardBrush}"/>
  <Setter Property="RowBackground" Value="{DynamicResource CardBrush}"/>
  <Setter Property="AlternatingRowBackground" Value="{DynamicResource GridAltBrush}"/>
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="RowHeight" Value="28"/>
  <Setter Property="ColumnHeaderHeight" Value="34"/>
</Style>
<Style TargetType="DataGridColumnHeader">
  <Setter Property="Background" Value="{DynamicResource GridHeaderBrush}"/>
  <Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
  <Setter Property="BorderThickness" Value="0,0,1,1"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
  <Setter Property="Padding" Value="10,0"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="DataGridColumnHeader">
    <Grid>
      <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}">
        <DockPanel>
          <Path x:Name="Arrow" DockPanel.Dock="Right" Width="8" Height="5" Margin="6,0,0,0" Stretch="Fill" Fill="{DynamicResource SubtleBrush}"
                Data="M 0 0 L 4 4 L 8 0 Z" Visibility="Collapsed" VerticalAlignment="Center"/>
          <ContentPresenter VerticalAlignment="Center"/>
        </DockPanel>
      </Border>
      <Thumb x:Name="PART_RightHeaderGripper" HorizontalAlignment="Right" Width="6" Cursor="SizeWE" Opacity="0"/>
    </Grid>
    <ControlTemplate.Triggers>
      <Trigger Property="SortDirection" Value="Ascending">
        <Setter TargetName="Arrow" Property="Visibility" Value="Visible"/>
        <Setter TargetName="Arrow" Property="Data" Value="M 0 4 L 4 0 L 8 4 Z"/>
      </Trigger>
      <Trigger Property="SortDirection" Value="Descending"><Setter TargetName="Arrow" Property="Visibility" Value="Visible"/></Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType="DataGridRow">
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource CardHoverBrush}"/></Trigger>
  </Style.Triggers>
</Style>
<Style TargetType="DataGridCell">
  <Setter Property="BorderThickness" Value="0"/>
  <Setter Property="Padding" Value="10,0"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="DataGridCell">
    <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
      <ContentPresenter VerticalAlignment="Center"/>
    </Border>
  </ControlTemplate></Setter.Value></Setter>
  <Style.Triggers>
    <Trigger Property="IsSelected" Value="True">
      <Setter Property="Background" Value="{DynamicResource SelectionBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    </Trigger>
  </Style.Triggers>
</Style>

<Style TargetType="ContextMenu">
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ContextMenu">
    <Border Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="6" Padding="3">
      <StackPanel IsItemsHost="True"/>
    </Border>
  </ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType="MenuItem">
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="MenuItem">
    <Border x:Name="Bd" Background="Transparent" CornerRadius="4" Padding="12,6" MinWidth="200">
      <ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/>
    </Border>
    <ControlTemplate.Triggers>
      <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource CardHoverBrush}"/></Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType="ToolTip">
  <Setter Property="Background" Value="{DynamicResource CardBrush}"/>
  <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
  <Setter Property="Padding" Value="8,5"/>
</Style>
<Style TargetType="GridSplitter">
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="HorizontalAlignment" Value="Stretch"/>
</Style>
<Style TargetType="ProgressBar">
  <Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/>
  <Setter Property="Background" Value="{DynamicResource LineBrush}"/>
  <Setter Property="BorderThickness" Value="0"/>
</Style>

<Style x:Key="Card" TargetType="Border">
  <Setter Property="Background" Value="{DynamicResource CardBrush}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="CornerRadius" Value="10"/>
  <Setter Property="Padding" Value="16,14"/>
  <Setter Property="Margin" Value="0,0,0,14"/>
</Style>
<Style x:Key="PageTitle" TargetType="TextBlock">
  <Setter Property="FontSize" Value="24"/>
  <Setter Property="FontWeight" Value="Bold"/>
</Style>
<Style x:Key="PageSubtitle" TargetType="TextBlock">
  <Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/>
  <Setter Property="Margin" Value="0,2,0,14"/>
  <Setter Property="TextWrapping" Value="Wrap"/>
</Style>
<Style x:Key="SectionTitle" TargetType="TextBlock">
  <Setter Property="FontSize" Value="15"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
  <Setter Property="Margin" Value="0,0,0,10"/>
</Style>
<Style x:Key="Hint" TargetType="TextBlock">
  <Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="TextWrapping" Value="Wrap"/>
  <Setter Property="Margin" Value="0,4,0,0"/>
</Style>
<Style x:Key="Label" TargetType="TextBlock">
  <Setter Property="VerticalAlignment" Value="Center"/>
  <Setter Property="Margin" Value="2,0,6,6"/>
</Style>
<Style x:Key="Counter" TargetType="TextBlock">
  <Setter Property="VerticalAlignment" Value="Center"/>
  <Setter Property="Margin" Value="8,0,6,6"/>
  <Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/>
</Style>
'@
}
