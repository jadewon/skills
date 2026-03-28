# remind

macOS 알림 타이머 스킬.

## Usage

```
/remind 5m 회의 시작
/remind 17:00 퇴근 준비
/remind 2h30m 빨래
```

자연어로도 사용 가능:

```
5분 뒤 회의 시작이라고 알림 설정 해줘
```

### Time formats

| Format | Example | Description |
|--------|---------|-------------|
| `Ns` | `30s` | N초 후 |
| `Nm` | `5m` | N분 후 |
| `Nh` | `2h` | N시간 후 |
| `NhNm` | `1h30m` | 복합 |
| `HH:MM` | `17:00` | 24시간제 절대 시각 |
| `Ham/pm` | `5pm` | 12시간제 절대 시각 |

## Example

![example](./example.png)
