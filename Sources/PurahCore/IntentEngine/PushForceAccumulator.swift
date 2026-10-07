// Sources/PurahCore/IntentEngine/PushForceAccumulator.swift
import Foundation
import CoreGraphics

/// 边缘推力阻力累加器 (Barrier / Input Leap / Loop 物理阻力墙模型)
///
/// 解决 macOS 光标在物理边框被底层卡死导致瞬时微分速度归零的物理困境：
/// 通过累加硬件层上报的相对位移增量 (Raw Motion Delta)，当累加量突破阻力墙阈值或短时间快速双击冲撞时击穿触发。
public struct PushForceAccumulator: Sendable {
    /// 当前累积的推力物理量 (Accumulated Raw Motion Force, 像素/点)
    public private(set) var accumulatedForce: Double = 0.0
    /// 最后一次有效向外推力时间戳
    public private(set) var lastPushTime: Date?
    /// 最后一次冲撞时间戳 (双击冲撞检测)
    public private(set) var lastImpulseTime: Date?
    /// 连续冲撞次数
    public private(set) var impulseCount: Int = 0

    /// 漏桶衰减超时：停止推边超过该时间后累积推力清零 (Barrier switchDelay 模型)
    public let decayTimeout: TimeInterval = 0.18
    /// 冲撞双击时间窗口 (Barrier switchDoubleTap 模型)
    public let doubleTapWindow: TimeInterval = 0.28

    public init() {}

    /// 接收推力事件并累加相对位移增量
    /// - Parameters:
    ///   - outwardDelta: 沿屏幕边缘向外推进的物理位移分量 (左轨向左推 > 0，右轨向右推 > 0)
    ///   - timestamp: 事件时间戳
    ///   - threshold: 阻力结界击穿阈值 (Resistance Barrier Threshold，默认 36.0px)
    /// - Returns: 是否突破阻力墙击穿 (Breakthrough)
    public mutating func push(
        outwardDelta: Double,
        timestamp: Date = Date(),
        threshold: Double = 36.0
    ) -> Bool {
        // 1. 若向屏幕内侧大幅明确回拉，立即重置累加器 (防误触保护)
        if outwardDelta <= -8.0 {
            reset()
            return false
        }

        // 若有轻微生理微弹 (-8.0 < outwardDelta < 0)，自然扣减推力但不彻底归零
        if outwardDelta < 0 {
            accumulatedForce = max(accumulatedForce + outwardDelta, 0.0)
            return false
        }

        // 仅处理向外推动的有效增量 (>= 0.2px)
        guard outwardDelta >= 0.2 else {
            // 若长时间无推力，按漏桶机制清零
            if let last = lastPushTime, timestamp.timeIntervalSince(last) > decayTimeout {
                reset()
            }
            return false
        }

        // 2. 检查漏桶时效：若距上次推力已超过 decayTimeout，重新开始累积
        if let last = lastPushTime, timestamp.timeIntervalSince(last) > decayTimeout {
            accumulatedForce = 0.0
            impulseCount = 0
        }

        // 3. 累加物理推力
        accumulatedForce += outwardDelta
        lastPushTime = timestamp

        // 4. 双击冲撞检测 (Barrier Double-Tap 冲击模型：单次冲击位移需达到 22px 以上的猛推)
        if outwardDelta >= 22.0 {
            if let lastImpulse = lastImpulseTime, timestamp.timeIntervalSince(lastImpulse) <= doubleTapWindow {
                impulseCount += 1
                if impulseCount >= 2 {
                    // 快速双次猛推直接击穿阻力墙
                    reset()
                    return true
                }
            } else {
                impulseCount = 1
                lastImpulseTime = timestamp
            }
        }

        // 5. 阻力墙击穿判定 (Resistance Barrier Threshold)
        if accumulatedForce >= threshold {
            reset()
            return true
        }

        return false
    }

    /// 重置推力累加器
    public mutating func reset() {
        accumulatedForce = 0.0
        lastPushTime = nil
        lastImpulseTime = nil
        impulseCount = 0
    }
}
