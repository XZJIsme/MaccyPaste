# 密码输入框中键盘快捷键不工作

语言：[English](keyboard-shortcut-password-fields.md)

## 问题描述

一些用户可能会遇到 MaccyPaste 键盘快捷键失效的问题，尤其是在密码输入框或安全输入场景中。常见原因是使用了会产生可见字符的快捷键，例如 `Option+C` 会生成 “ç” 字符。

## 根本原因

macOS 会在安全输入框中阻止输出文本的键盘事件监听。当某个键盘组合会生成字符时，例如 `Option+C` -> “ç”，macOS 的安全机制会阻止第三方应用在密码输入框和其他安全输入场景中拦截这些按键事件。

## 简单解决方案

选择不同的快捷键：使用不会产生可见字符的键盘组合，例如 `Cmd+Shift+V`。

## 详细解决方案：如果你确实想继续使用当前快捷键

如果你想使用一个已被系统使用且会产生文本输出的快捷键，可以用 Karabiner-Elements 把它重映射到另一个快捷键。例如，把 `Option+C` 重映射为 `Cmd+Shift+C`。

### 使用 Karabiner-Elements

1. **下载并安装 Karabiner-Elements**

   - 访问：<https://karabiner-elements.pqrs.org/>
   - 下载并安装应用
   - 按提示授予必要权限

2. **配置按键重映射**

   - 打开 Karabiner-Elements
   - 进入 “Complex Modifications”
   - 点击 “Add your own rule”
   - 粘贴下面的 JSON 配置
   - 如需编辑不同按键组合，修改 `key_code` 和 `modifiers` 的值
   - 给规则起一个名字，例如 “Remap Option+C to Cmd+Shift+C for clipboard manager”

3. **Karabiner 规则示例**

   这个例子会把 `Option+C` 重映射为 `Cmd+Shift+C`：

   ```json
   {
     "description": "Remap option+c to cmd+shift+c for MaccyPaste trigger",
     "manipulators": [
       {
         "from": {
           "key_code": "c",
           "modifiers": {
             "mandatory": ["left_alt"],
             "optional": ["any"]
           }
         },
         "to": [
           {
             "key_code": "c",
             "modifiers": ["left_command", "left_shift"]
           }
         ],
         "type": "basic"
       }
     ]
   }
   ```

4. **更新 MaccyPaste 设置**

   - 打开 MaccyPaste preferences
   - 把键盘快捷键设置为 Karabiner 重映射后的组合，例如 `Cmd+Shift+C`
   - 在不同场景中测试快捷键，包括密码输入框

## 其他方案

* **选择不同快捷键**：使用不会产生可见字符的组合，例如 `Cmd+Shift+V`
* **系统键盘设置**：调整可能与目标快捷键冲突的系统快捷键

## 验证

完成设置后：

1. 在普通文本输入框中测试快捷键
2. 在密码输入框中测试快捷键
3. 在安全类应用中测试快捷键，例如银行应用、密码管理器
4. 确认 MaccyPaste 在这些场景中都能稳定响应

这种做法可以保留你喜欢的按键组合，同时兼容 macOS 的安全输入机制。
