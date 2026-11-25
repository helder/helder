# Popups, shortcuts and dragging

Popups draw in a layer over the view, clear of the parent's clipping.
Use `Popover` for a menu anchored to its trigger or for a modal dialog.
A modal keeps focus inside, and Escape or a press outside calls
`onDismiss`.

<Example id="mail"/>

This dialog uses a `Button` component that takes a label, a tag and a
click handler. One signal opens and closes the popup.

```haxe
static function Confirm(props:{onYes:Void->Void}):View {
  var open = signal(false);
  return <view>
    <Button tag='delete' label='Delete' onClick={() -> open(true)}/>
    <Popover open={open} modal placement='center' onDismiss={() -> open(false)}>
      <view role='dialog' label='Delete this file?' padding={16} row-gap={12} radius={8} background='#ffffff'>
        <text font-weight={700}>Delete this file?</text>
        <view direction='row' column-gap={8} justify='end'>
          <Button tag='no' label='Cancel' onClick={() -> open(false)}/>
          <Button tag='yes' label='Delete' onClick={() -> {
            open(false);
            props.onYes();
          }}/>
        </view>
      </view>
    </Popover>
  </view>;
}
```

A keymap binds keys to named actions. Handlers dispatch from the focused
view up through its parents. Put a `key-context` on a view to give its
shortcuts a scope.

```haxe
static function Editor(props:{text:Signal<String>, onSave:Void->Void}):View
  return <view row-gap={8} key-context='Editor' actions={[helder.ui.actions.Actions.handle(EditorAction, a -> {
    switch a {
      case Save: props.onSave();
      case Clear: props.text('');
    }
    true;
  })]}>
    <field:textarea label='Text' value={props.text} onInput={e -> props.text(e.text)}/>
  </view>;
```

Register the actions with `Actions.actions` and bind keys with
`Keymap.global.bind`. A handler returns `true` when it takes an action.
In bindings, `secondary` means Command on macOS and Control elsewhere.

## What else

- **Placement:** a popover can sit below, above, to either side, in the centre or at a point. Use a role and label for a custom dialog.
- **Drag and drop:** set `drag-data` on a source. A target calls `preventDefault()` in `onDragOver` to accept it and reads `e.data` in `onDrop`. Clear the hover style in `onDragLeave` and `onDrop`.
- **Accessibility:** set a role and label for custom controls, and make them focusable and operable from the keyboard. Standard controls already do this.

<Reference to="ui,view"/>
