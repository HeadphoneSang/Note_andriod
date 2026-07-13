## 登录流程
```python
[ App 启动 ]
     │
     ▼
[ 读取本地 Token ] ──( 无 Token )──> 跳转到 [ 登录页 ]
     │
 ( 有 Token )
     ▼
[ 请求“获取用户信息”接口 ] (Header 携带 Token)
     │
     ├───────> (服务器返回 200: Token 有效) ──> [ 更新用户信息，直接进首页 ]
     │
     └───────> (服务器返回 401: Token 过期) ──> [ 清除本地 Token，跳转到登录页 ]
```
## 补充：
1. 使用Redis完善功能：
- 使用Redis对传入服务器的token进行第一层过滤，比如用户点击了exit，就把他的token加入到redis的black_ls_token_set中，然后过期时间设成标准的token到期时间。这样可以防止token没有过期，但是用户已经退出登录，这个token被滥用。
- 使用Redis限制登录次数，每次用户登录失败就给对应的key加1，并且设置过期时间n 秒，然后当失败次数大于5时，就退出不允许登录，返回剩余过期时间。示例:
```python
# 1. 用户输入密码错误，后端开始执行：
Redis.INCR("login:fail:13800138000")  # 错误次数 +1

# 2. 如果是今天第一次输错（通过判断次数是否为 1），就给它加个 1 小时过期的紧箍咒
if 错误次数 == 1:
    Redis.EXPIRE("login:fail:13800138000", 3600)

# 3. 检查他一共输错了多少次
current_fails = Redis.GET("login:fail:13800138000")

if current_fails >= 5:
    return "错误次数过多，账号已被锁定，请 1 小时后再试"
else:
    return "密码错误，你还可以尝试 " + (5 - current_fails) + " 次"
```