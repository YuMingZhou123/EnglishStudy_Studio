# 权限模型设计

版本：v0.1  
日期：2026-05-27  
状态：第一版模型，MVP 仅启用核心权限关系

## 1. 设计目标

第一版先设计完整权限基础模型，但只启用最小核心：

- User
- Role
- Permission
- UserRole
- RolePermission

这样既能支撑 MVP 的用户端和管理端权限，又为后续菜单权限、按钮权限、机构端、班级、教师端和数据权限预留扩展空间。

## 2. 当前启用模型

```text
User <-> UserRole <-> Role <-> RolePermission <-> Permission
```

含义：

- 一个用户可以拥有多个角色。
- 一个角色可以分配给多个用户。
- 一个角色可以拥有多个权限。
- 一个权限可以被多个角色拥有。

## 3. 后端实现方案

认证和用户角色关系基于 ASP.NET Core Identity：

- `ApplicationUser`
- `ApplicationRole`
- `ApplicationUserRole`

业务权限扩展由项目自定义：

- `Permission`
- `RolePermission`

数据库表命名：

```text
users
roles
user_roles
permissions
role_permissions
```

Identity 相关辅助表：

```text
user_claims
role_claims
user_logins
user_tokens
```

### 3.1 第一版落地状态

当前代码已经启用最小权限链路：

- `AppPermissions.ContentManage = content:manage`
- 开发环境启动时写入 `Permission` 和 `RolePermission`
- `Admin`、`ContentAdmin`、`SuperAdmin` 默认拥有 `content:manage`
- 后台内容接口使用 `[Authorize(Policy = AppPermissions.ContentManage)]`
- 授权处理器通过 `UserRole -> RolePermission -> Permission` 判断当前用户是否拥有权限

第一版暂时不做可视化权限配置后台，权限先通过种子数据和后续迁移脚本维护。

## 4. Permission 编码规则

权限使用稳定字符串编码：

```text
resource:action
```

示例：

```text
admin:access
sentence:read
sentence:create
sentence:update
sentence:delete
sentence:publish
word:read
word:create
word:update
word:delete
media:upload
dictation:practice
vocabulary:review
```

## 5. Permission 类型

`Permission.Type` 用于区分权限用途：

```text
api
menu
button
data
```

MVP 阶段主要启用 `api` 权限。菜单和按钮权限可以先使用同一张 `permissions` 表承载，后续需要复杂菜单树时再新增 `menus` 表。

## 6. 第一版角色建议

```text
SuperAdmin
Admin
ContentAdmin
Learner
```

说明：

- `SuperAdmin`：平台最高权限。
- `Admin`：平台管理权限。
- `ContentAdmin`：句子、单词、音频等内容管理权限。
- `Learner`：普通学习用户。

## 7. 后续扩展方向

### 7.1 菜单权限

简单阶段：

```text
menu:dashboard
menu:sentences
menu:words
menu:users
```

复杂阶段再引入：

```text
menus
role_menus
```

### 7.2 按钮权限

直接使用权限码：

```text
sentence:create
sentence:update
sentence:delete
sentence:publish
```

前端控制按钮显示，后端控制接口访问。

### 7.3 数据权限

后续机构端、班级、教师端出现后再启用：

```text
All
Organization
Class
Own
Custom
```

实体中可以逐步增加：

```text
organization_id
class_id
created_by
```

查询时由后端统一应用数据范围过滤。

## 8. MVP 取舍

第一版实现：

- Identity 用户。
- Identity 角色。
- 用户角色中间表。
- 权限表。
- 角色权限中间表。

第一版暂不实现：

- 可视化权限配置后台。
- 复杂菜单树。
- 复杂按钮权限管理。
- 组织、部门、班级。
- 数据范围规则引擎。
