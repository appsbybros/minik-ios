import Foundation

// AndroidKit: the legacy jdk.internal.math.FloatingDecimal binary-to-decimal conversion, ported statement by
// statement from Android libcore main (identical to the JDK's BinaryToASCIIBuffer: dtoa, developLongDigits,
// estimateDecExp, roundup, getChars) and FormattedFloatingDecimal (applyPrecision, fillDecimal,
// fillScientific). Android uses it for Double.toString / String.valueOf(double) on every version (and so for
// org.json numbers), for Float.toString up to Android 15, and for the digits of java.util.Formatter
// %e/%f/%g. FDBigInteger is replaced by an exact little unsigned big integer: the algorithm only needs exact
// products by powers of 2 and 5, quotients below 10, sums and comparisons, so the digits are identical.

enum AKotlinFloatingDecimal {
    // MARK: Constants (FloatingDecimal, DoubleConsts, FloatConsts)

    static let EXP_SHIFT = 52
    static let FRACT_HOB: Int64 = 1 << 52
    static let EXP_ONE: Int64 = 1023 << 52
    static let MAX_SMALL_BIN_EXP = 62
    static let MIN_SMALL_BIN_EXP = -(63 / 3)
    static let SIGN_BIT_MASK: Int64 = Int64.min
    static let EXP_BIT_MASK: Int64 = 0x7FF0_0000_0000_0000
    static let SIGNIF_BIT_MASK: Int64 = 0x000F_FFFF_FFFF_FFFF

    /// FDBigInteger.SMALL_5_POW: 5^0 ... 5^13.
    static let SMALL_5_POW: [Int32] = [
        1, 5, 25, 125, 625, 3125, 15625, 78125, 390625, 1953125, 9765625, 48828125, 244140625, 1220703125,
    ]

    /// FDBigInteger.LONG_5_POW: 5^0 ... 5^26.
    static let LONG_5_POW: [Int64] = [
        1, 5, 25, 125, 625, 3125, 15625, 78125, 390625, 1953125, 9765625, 48828125, 244140625, 1220703125,
        6103515625, 30517578125, 152587890625, 762939453125, 3814697265625, 19073486328125, 95367431640625,
        476837158203125, 2384185791015625, 11920928955078125, 59604644775390625, 298023223876953125,
        1490116119384765625,
    ]

    /// BinaryToASCIIBuffer.N_5_BITS: approximately ceil(log2(5^i)).
    static let N_5_BITS: [Int] = [
        0, 3, 5, 7, 10, 12, 14, 17, 19, 21, 24, 26, 28, 31, 33, 35, 38, 40, 42, 45, 47, 49, 52, 54, 56, 59, 61,
    ]

    /// BinaryToASCIIBuffer.insignificantDigitsNumber.
    static let insignificantDigitsNumber: [Int] = [
        0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3,
        4, 4, 4, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7,
        8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 11, 11, 11,
        12, 12, 12, 12, 13, 13, 13, 14, 14, 14,
        15, 15, 15, 15, 16, 16, 16, 17, 17, 17,
        18, 18, 18, 19,
    ]

    // MARK: Entry points

    /// FloatingDecimal.toJavaFormatString(double) = Android `Double.toString(d)`.
    static func toJavaFormatString(_ d: Double) -> String {
        return converter(d, isCompatibleFormat: true).toJavaFormatString()
    }

    /// FloatingDecimal.toJavaFormatString(float) = Android <= 15 `Float.toString(f)`.
    static func toJavaFormatString(_ f: Float) -> String {
        return converter(f).toJavaFormatString()
    }

    /// FloatingDecimal.getBinaryToASCIIConverter(double, isCompatibleFormat).
    static func converter(_ d: Double, isCompatibleFormat: Bool) -> Buffer {
        let dBits = Int64(bitPattern: d.bitPattern)
        let isNegative = (dBits & SIGN_BIT_MASK) != 0 // discover sign
        var fractBits = dBits & SIGNIF_BIT_MASK
        var binExp = Int((dBits & EXP_BIT_MASK) &>> Int64(EXP_SHIFT))
        // Discover obvious special cases of NaN and Infinity.
        if binExp == Int(EXP_BIT_MASK &>> Int64(EXP_SHIFT)) {
            if fractBits == 0 {
                return Buffer(exceptional: isNegative ? "-Infinity" : "Infinity", isNegative: isNegative)
            }
            return Buffer(exceptional: "NaN", isNegative: false)
        }
        // Finish unpacking. Normalize denormalized numbers. Insert assumed high-order bit for normalized
        // numbers. Subtract exponent bias.
        let nSignificantBits: Int
        if binExp == 0 {
            if fractBits == 0 {
                // not a denorm, just a 0!
                return Buffer(zeroNegative: isNegative)
            }
            let leadingZeros = fractBits.leadingZeroBitCount
            let shift = leadingZeros - (63 - EXP_SHIFT)
            fractBits = fractBits &<< Int64(shift)
            binExp = 1 - shift
            nSignificantBits = 64 - leadingZeros // recall binExp is - shift count.
        } else {
            fractBits |= FRACT_HOB
            nSignificantBits = EXP_SHIFT + 1
        }
        binExp -= 1023
        let buf = Buffer()
        buf.isNegative = isNegative
        // call the routine that actually does all the hard work.
        buf.dtoa(binExp, fractBits, nSignificantBits, isCompatibleFormat)
        return buf
    }

    /// FloatingDecimal.getBinaryToASCIIConverter(float).
    static func converter(_ f: Float) -> Buffer {
        let fBits = Int32(bitPattern: f.bitPattern)
        let isNegative = (fBits & Int32.min) != 0
        var fractBits = fBits & 0x007F_FFFF
        var binExp = Int((fBits & 0x7F80_0000) &>> 23)
        // Discover obvious special cases of NaN and Infinity.
        if binExp == 0xFF {
            if fractBits == 0 {
                return Buffer(exceptional: isNegative ? "-Infinity" : "Infinity", isNegative: isNegative)
            }
            return Buffer(exceptional: "NaN", isNegative: false)
        }
        let nSignificantBits: Int
        if binExp == 0 {
            if fractBits == 0 {
                // not a denorm, just a 0!
                return Buffer(zeroNegative: isNegative)
            }
            let leadingZeros = fractBits.leadingZeroBitCount
            let shift = leadingZeros - (31 - 23)
            fractBits = fractBits &<< Int32(shift)
            binExp = 1 - shift
            nSignificantBits = 32 - leadingZeros // recall binExp is - shift count.
        } else {
            fractBits |= 1 << 23
            nSignificantBits = 23 + 1
        }
        binExp -= 127
        let buf = Buffer()
        buf.isNegative = isNegative
        // call the routine that actually does all the hard work.
        buf.dtoa(binExp, Int64(fractBits) &<< Int64(EXP_SHIFT - 23), nSignificantBits, true)
        return buf
    }

    // MARK: BinaryToASCIIBuffer

    final class Buffer {
        var isNegative = false
        var decExponent = 0
        var firstDigitIndex = 0
        var nDigits = 0
        var digits: [UInt8] = Array(repeating: 0x30, count: 20)
        /// "Infinity", "-Infinity" or "NaN" for the exceptional converters.
        private(set) var exceptional: String?
        // True if the dtoa() binary to decimal conversion was exact.
        var exactDecimalConversion = false
        // True if the result was rounded-up at the end of the conversion process.
        var decimalDigitsRoundedUp = false

        init() {}

        init(exceptional: String, isNegative: Bool) {
            self.exceptional = exceptional
            self.isNegative = isNegative
        }

        /// B2AC_POSITIVE_ZERO / B2AC_NEGATIVE_ZERO: digits {'0'}, decExponent 0.
        init(zeroNegative: Bool) {
            isNegative = zeroNegative
            decExponent = 0
            digits = [0x30]
            firstDigitIndex = 0
            nDigits = 1
        }

        var isExceptional: Bool { return exceptional != nil }

        /// getDigits: the significant digits (ASCII).
        func getDigits() -> [UInt8] {
            return Array(digits[firstDigitIndex..<(firstDigitIndex + nDigits)])
        }

        /// getDecimalExponent.
        func getDecimalExponent() -> Int {
            return decExponent
        }

        func toJavaFormatString() -> String {
            if let image = exceptional { return image }
            return getChars()
        }

        /// The easy subcase: all the significant bits, after scaling, are held in lvalue (lvalue > 0).
        private func developLongDigits(_ decExponentIn: Int, _ lvalueIn: Int64, _ insignificantDigits: Int) {
            var decExponent = decExponentIn
            var lvalue = lvalueIn
            if insignificantDigits != 0 {
                // Discard non-significant low-order bits, while rounding, up to insignificant value.
                let pow10 = AKotlinFloatingDecimal.LONG_5_POW[insignificantDigits] &<< Int64(insignificantDigits)
                let residue = lvalue % pow10
                lvalue /= pow10
                decExponent += insignificantDigits
                if residue >= (pow10 &>> 1) {
                    // round up based on the low-order bits we're discarding
                    lvalue += 1
                }
            }
            var digitno = digits.count - 1
            var c: Int
            if lvalue <= Int64(Int32.max) {
                // even easier subcase! can do int arithmetic rather than long!
                var ivalue = Int32(truncatingIfNeeded: lvalue)
                c = Int(ivalue % 10)
                ivalue /= 10
                while c == 0 {
                    decExponent += 1
                    c = Int(ivalue % 10)
                    ivalue /= 10
                }
                while ivalue != 0 {
                    digits[digitno] = UInt8(0x30 + c)
                    digitno -= 1
                    decExponent += 1
                    c = Int(ivalue % 10)
                    ivalue /= 10
                }
                digits[digitno] = UInt8(0x30 + c)
            } else {
                // same algorithm as above (same bugs, too) but using long arithmetic.
                c = Int(lvalue % 10)
                lvalue /= 10
                while c == 0 {
                    decExponent += 1
                    c = Int(lvalue % 10)
                    lvalue /= 10
                }
                while lvalue != 0 {
                    digits[digitno] = UInt8(0x30 + c)
                    digitno -= 1
                    decExponent += 1
                    c = Int(lvalue % 10)
                    lvalue /= 10
                }
                digits[digitno] = UInt8(0x30 + c)
            }
            self.decExponent = decExponent + 1
            self.firstDigitIndex = digitno
            self.nDigits = digits.count - digitno
        }

        func dtoa(_ binExp: Int, _ fractBitsIn: Int64, _ nSignificantBits: Int, _ isCompatibleFormat: Bool) {
            var fractBits = fractBitsIn
            // Examine number. Determine if it is an easy case, which we can do pretty trivially using
            // float/long conversion, or whether we must do real work.
            let tailZeros = fractBits.trailingZeroBitCount

            // number of significant bits of fractBits;
            let nFractBits = AKotlinFloatingDecimal.EXP_SHIFT + 1 - tailZeros

            // reset flags to default values as dtoa() does not always set these flags.
            decimalDigitsRoundedUp = false
            exactDecimalConversion = false

            // number of significant bits to the right of the point.
            let nTinyBits = Swift.max(0, nFractBits - binExp - 1)
            if binExp <= AKotlinFloatingDecimal.MAX_SMALL_BIN_EXP && binExp >= AKotlinFloatingDecimal.MIN_SMALL_BIN_EXP {
                // Look more closely at the number to decide if, with scaling by 10^nTinyBits, the result will
                // fit in a long.
                if nTinyBits < AKotlinFloatingDecimal.LONG_5_POW.count
                    && (nFractBits + AKotlinFloatingDecimal.N_5_BITS[nTinyBits]) < 64 {
                    if nTinyBits == 0 {
                        let insignificant: Int
                        if binExp > nSignificantBits {
                            insignificant = AKotlinFloatingDecimal.insignificantDigitsForPow2(binExp - nSignificantBits - 1)
                        } else {
                            insignificant = 0
                        }
                        if binExp >= AKotlinFloatingDecimal.EXP_SHIFT {
                            fractBits = fractBits &<< Int64(binExp - AKotlinFloatingDecimal.EXP_SHIFT)
                        } else {
                            fractBits = Int64(bitPattern: UInt64(bitPattern: fractBits) &>> UInt64(AKotlinFloatingDecimal.EXP_SHIFT - binExp))
                        }
                        developLongDigits(0, fractBits, insignificant)
                        return
                    }
                    // (The nTinyBits > 0 shortcut is commented out in the Java source.)
                }
            }
            // This is the hard case. We are going to compute large positive integers B and S and integer
            // decExp, s.t. d = (B / S) * 10^decExp, 1 <= B / S < 10, and M = 1/2 ULP of d scaled like B.
            var decExp = AKotlinFloatingDecimal.estimateDecExp(fractBits, binExp)
            var B2: Int, B5: Int // powers of 2 and powers of 5, respectively, in B
            var S2: Int, S5: Int // powers of 2 and powers of 5, respectively, in S
            var M2: Int, M5: Int // powers of 2 and powers of 5, respectively, in M

            B5 = Swift.max(0, -decExp)
            B2 = B5 + nTinyBits + binExp

            S5 = Swift.max(0, decExp)
            S2 = S5 + nTinyBits

            M5 = B5
            M2 = B2 - nSignificantBits

            // Shift out the trailing zeros of fractBits before turning it into a big integer.
            fractBits = Int64(bitPattern: UInt64(bitPattern: fractBits) &>> UInt64(tailZeros))
            B2 -= nFractBits - 1
            let common2factor = Swift.min(B2, S2)
            B2 -= common2factor
            S2 -= common2factor
            M2 -= common2factor

            // HACK!! For exact powers of two, the next smallest number is only half as far away as we think.
            if nFractBits == 1 {
                M2 -= 1
            }

            if M2 < 0 {
                // since we cannot scale M down far enough, we must scale the other values up.
                B2 -= M2
                S2 -= M2
                M2 = 0
            }

            var ndigit = 0
            var low: Bool
            var high: Bool
            var lowDigitDifference: Int64
            var q: Int

            // binary digits needed to represent B, approx.
            let Bbits = nFractBits + B2 + (B5 < AKotlinFloatingDecimal.N_5_BITS.count ? AKotlinFloatingDecimal.N_5_BITS[B5] : B5 * 3)

            // binary digits needed to represent 10*S, approx.
            let tenSbits = S2 + 1 + ((S5 + 1) < AKotlinFloatingDecimal.N_5_BITS.count ? AKotlinFloatingDecimal.N_5_BITS[S5 + 1] : (S5 + 1) * 3)
            if Bbits < 64 && tenSbits < 64 {
                if Bbits < 32 && tenSbits < 32 {
                    // wa-hoo! They're all ints!
                    var b = (Int32(truncatingIfNeeded: fractBits) &* AKotlinFloatingDecimal.SMALL_5_POW[B5]) &<< Int32(B2)
                    let s = AKotlinFloatingDecimal.SMALL_5_POW[S5] &<< Int32(S2)
                    var m = AKotlinFloatingDecimal.SMALL_5_POW[M5] &<< Int32(M2)
                    let tens = s &* 10
                    // Unroll the first iteration. If our decExp estimate was too high, our first quotient will
                    // be zero. In this case, we discard it and decrement decExp.
                    ndigit = 0
                    q = Int(b / s)
                    b = 10 &* (b % s)
                    m = m &* 10
                    low = b < m
                    high = (b &+ m) > tens
                    if q == 0 && !high {
                        // oops. Usually ignore leading zero.
                        decExp -= 1
                    } else {
                        digits[ndigit] = UInt8(0x30 + q)
                        ndigit += 1
                    }
                    // HACK! Java spec sez that we always have at least one digit after the . in either F- or
                    // E-form output. Thus we will need more than one digit if we're using E-form.
                    if !isCompatibleFormat || decExp < -3 || decExp >= 8 {
                        high = false
                        low = false
                    }
                    while !low && !high {
                        q = Int(b / s)
                        b = 10 &* (b % s)
                        m = m &* 10
                        if m > 0 {
                            low = b < m
                            high = (b &+ m) > tens
                        } else {
                            // hack -- m might overflow!
                            low = true
                            high = true
                        }
                        digits[ndigit] = UInt8(0x30 + q)
                        ndigit += 1
                    }
                    lowDigitDifference = Int64((b &<< 1) &- tens)
                    exactDecimalConversion = b == 0
                } else {
                    // still good! they're all longs!
                    var b = (fractBits &* AKotlinFloatingDecimal.LONG_5_POW[B5]) &<< Int64(B2)
                    let s = AKotlinFloatingDecimal.LONG_5_POW[S5] &<< Int64(S2)
                    var m = AKotlinFloatingDecimal.LONG_5_POW[M5] &<< Int64(M2)
                    let tens = s &* 10
                    // Unroll the first iteration.
                    ndigit = 0
                    q = Int(b / s)
                    b = 10 &* (b % s)
                    m = m &* 10
                    low = b < m
                    high = (b &+ m) > tens
                    if q == 0 && !high {
                        // oops. Usually ignore leading zero.
                        decExp -= 1
                    } else {
                        digits[ndigit] = UInt8(0x30 + q)
                        ndigit += 1
                    }
                    if !isCompatibleFormat || decExp < -3 || decExp >= 8 {
                        high = false
                        low = false
                    }
                    while !low && !high {
                        q = Int(b / s)
                        b = 10 &* (b % s)
                        m = m &* 10
                        if m > 0 {
                            low = b < m
                            high = (b &+ m) > tens
                        } else {
                            // hack -- m might overflow!
                            low = true
                            high = true
                        }
                        digits[ndigit] = UInt8(0x30 + q)
                        ndigit += 1
                    }
                    lowDigitDifference = (b &<< 1) &- tens
                    exactDecimalConversion = b == 0
                }
            } else {
                // We really must do big-integer arithmetic. (FDBigInteger also scales every value by the same
                // normalization shift, which changes no quotient and no comparison.)
                let Sval = BigUInt.valueOfPow52(S5, S2)
                var Bval = BigUInt.valueOfMulPow52(UInt64(bitPattern: fractBits), B5, B2)
                var Mval = BigUInt.valueOfPow52(M5 + 1, M2 + 1)
                let tenSval = BigUInt.valueOfPow52(S5 + 1, S2 + 1)
                // Unroll the first iteration.
                ndigit = 0
                q = Bval.quoRemIteration(Sval)
                low = Bval.cmp(Mval) < 0
                high = tenSval.cmp(Bval.plus(Mval)) <= 0
                if q == 0 && !high {
                    // oops. Usually ignore leading zero.
                    decExp -= 1
                } else {
                    digits[ndigit] = UInt8(0x30 + q)
                    ndigit += 1
                }
                if !isCompatibleFormat || decExp < -3 || decExp >= 8 {
                    high = false
                    low = false
                }
                while !low && !high {
                    q = Bval.quoRemIteration(Sval)
                    Mval.multiply(by: 10)
                    low = Bval.cmp(Mval) < 0
                    high = tenSval.cmp(Bval.plus(Mval)) <= 0
                    digits[ndigit] = UInt8(0x30 + q)
                    ndigit += 1
                }
                if high && low {
                    Bval = Bval.leftShift(1)
                    lowDigitDifference = Int64(Bval.cmp(tenSval))
                } else {
                    lowDigitDifference = 0 // this here only for flow analysis!
                }
                exactDecimalConversion = Bval.isZero
            }
            self.decExponent = decExp + 1
            self.firstDigitIndex = 0
            self.nDigits = ndigit
            // Last digit gets rounded based on stopping condition.
            if high {
                if low {
                    if lowDigitDifference == 0 {
                        // it's a tie! choose based on which digits we like.
                        if (digits[firstDigitIndex + nDigits - 1] & 1) != 0 {
                            roundup()
                        }
                    } else if lowDigitDifference > 0 {
                        roundup()
                    }
                } else {
                    roundup()
                }
            }
        }

        /// Add one to the least significant digit; in the unlikely event there is a carry out, deal with it.
        private func roundup() {
            var i = firstDigitIndex + nDigits - 1
            var q = digits[i]
            if q == 0x39 {
                while q == 0x39 && i > firstDigitIndex {
                    digits[i] = 0x30
                    i -= 1
                    q = digits[i]
                }
                if q == 0x39 {
                    // carryout! High-order 1, rest 0s, larger exp.
                    decExponent += 1
                    digits[firstDigitIndex] = 0x31
                    return
                }
                // else fall through.
            }
            digits[i] = q + 1
            decimalDigitsRoundedUp = true
        }

        /// BinaryToASCIIBuffer.getChars: the Java format ("1.0", "0.001", "1.0E-4", "1.234E7").
        private func getChars() -> String {
            var result: [UInt8] = []
            result.reserveCapacity(26)
            if isNegative {
                result.append(0x2D)
            }
            let first = firstDigitIndex
            if decExponent > 0 && decExponent < 8 {
                // print digits.digits.
                var charLength = Swift.min(nDigits, decExponent)
                result.append(contentsOf: digits[first..<(first + charLength)])
                if charLength < decExponent {
                    charLength = decExponent - charLength
                    for _ in 0..<charLength { result.append(0x30) }
                    result.append(0x2E)
                    result.append(0x30)
                } else {
                    result.append(0x2E)
                    if charLength < nDigits {
                        result.append(contentsOf: digits[(first + charLength)..<(first + nDigits)])
                    } else {
                        result.append(0x30)
                    }
                }
            } else if decExponent <= 0 && decExponent > -3 {
                result.append(0x30)
                result.append(0x2E)
                if decExponent != 0 {
                    for _ in 0..<(-decExponent) { result.append(0x30) }
                }
                result.append(contentsOf: digits[first..<(first + nDigits)])
            } else {
                result.append(digits[first])
                result.append(0x2E)
                if nDigits > 1 {
                    result.append(contentsOf: digits[(first + 1)..<(first + nDigits)])
                } else {
                    result.append(0x30)
                }
                result.append(0x45)
                var e: Int
                if decExponent <= 0 {
                    result.append(0x2D)
                    e = -decExponent + 1
                } else {
                    e = decExponent - 1
                }
                // decExponent has 1, 2, or 3, digits
                if e <= 9 {
                    result.append(UInt8(e + 0x30))
                } else if e <= 99 {
                    result.append(UInt8(e / 10 + 0x30))
                    result.append(UInt8(e % 10 + 0x30))
                } else {
                    result.append(UInt8(e / 100 + 0x30))
                    e %= 100
                    result.append(UInt8(e / 10 + 0x30))
                    result.append(UInt8(e % 10 + 0x30))
                }
            }
            return String(decoding: result, as: UTF8.self)
        }
    }

    /// BinaryToASCIIBuffer.estimateDecExp: floor(log10(d)) estimate (never too low).
    static func estimateDecExp(_ fractBits: Int64, _ binExp: Int) -> Int {
        let d2 = Double(bitPattern: UInt64(bitPattern: EXP_ONE | (fractBits & SIGNIF_BIT_MASK)))
        let d = (d2 - 1.5) * 0.289529654 + 0.176091259 + Double(binExp) * 0.301029995663981
        let dBits = Int64(bitPattern: d.bitPattern) // can't be NaN here so use raw
        let exponent = Int((dBits & EXP_BIT_MASK) &>> Int64(EXP_SHIFT)) - 1023
        let isNegative = (dBits & SIGN_BIT_MASK) != 0 // discover sign
        if exponent >= 0 && exponent < 52 { // hot path
            let mask = SIGNIF_BIT_MASK &>> Int64(exponent)
            let r = Int(Int32(truncatingIfNeeded: ((dBits & SIGNIF_BIT_MASK) | FRACT_HOB) &>> Int64(EXP_SHIFT - exponent)))
            return isNegative ? ((mask & dBits) == 0 ? -r : -r - 1) : r
        } else if exponent < 0 {
            return (dBits & ~SIGN_BIT_MASK) == 0 ? 0 : (isNegative ? -1 : 0)
        } else { // if (exponent >= 52)
            return Int(KMath.d2i(d))
        }
    }

    /// insignificantDigitsForPow2(v) == insignificantDigits(1L << v).
    static func insignificantDigitsForPow2(_ p2: Int) -> Int {
        if p2 > 1 && p2 < insignificantDigitsNumber.count {
            return insignificantDigitsNumber[p2]
        }
        return 0
    }

    // MARK: FDBigInteger (exact unsigned arithmetic)

    struct BigUInt {
        /// Little-endian 32-bit words without leading (high) zero words.
        private(set) var words: [UInt32]

        init(_ value: UInt64) {
            words = [UInt32(truncatingIfNeeded: value), UInt32(truncatingIfNeeded: value >> 32)]
            trim()
        }

        private init(words: [UInt32]) {
            self.words = words
            trim()
        }

        private mutating func trim() {
            while let last = words.last, last == 0 { words.removeLast() }
        }

        var isZero: Bool { return words.isEmpty }

        /// 5^p5 * 2^p2.
        static func valueOfPow52(_ p5: Int, _ p2: Int) -> BigUInt {
            return valueOfMulPow52(1, p5, p2)
        }

        /// value * 5^p5 * 2^p2.
        static func valueOfMulPow52(_ value: UInt64, _ p5: Int, _ p2: Int) -> BigUInt {
            var result = BigUInt(value)
            var p = p5
            while p >= 13 {
                result.multiply(by: 1_220_703_125)
                p -= 13
            }
            if p > 0 {
                result.multiply(by: UInt32(AKotlinFloatingDecimal.SMALL_5_POW[p]))
            }
            return result.leftShift(p2)
        }

        mutating func multiply(by factor: UInt32) {
            var carry: UInt64 = 0
            for i in words.indices {
                let product = UInt64(words[i]) * UInt64(factor) + carry
                words[i] = UInt32(truncatingIfNeeded: product)
                carry = product >> 32
            }
            if carry != 0 { words.append(UInt32(truncatingIfNeeded: carry)) }
            trim()
        }

        func leftShift(_ shift: Int) -> BigUInt {
            if isZero || shift == 0 { return self }
            let wordShift = shift / 32
            let bitShift = shift % 32
            var out = [UInt32](repeating: 0, count: wordShift)
            if bitShift == 0 {
                out.append(contentsOf: words)
            } else {
                var carry: UInt32 = 0
                for w in words {
                    out.append((w << UInt32(bitShift)) | carry)
                    carry = w >> UInt32(32 - bitShift)
                }
                if carry != 0 { out.append(carry) }
            }
            return BigUInt(words: out)
        }

        /// -1, 0 or 1.
        func cmp(_ other: BigUInt) -> Int {
            if words.count != other.words.count { return words.count < other.words.count ? -1 : 1 }
            var i = words.count - 1
            while i >= 0 {
                if words[i] != other.words[i] { return words[i] < other.words[i] ? -1 : 1 }
                i -= 1
            }
            return 0
        }

        func plus(_ other: BigUInt) -> BigUInt {
            let n = Swift.max(words.count, other.words.count)
            var out: [UInt32] = []
            out.reserveCapacity(n + 1)
            var carry: UInt64 = 0
            for i in 0..<n {
                let a = i < words.count ? UInt64(words[i]) : 0
                let b = i < other.words.count ? UInt64(other.words[i]) : 0
                let sum = a + b + carry
                out.append(UInt32(truncatingIfNeeded: sum))
                carry = sum >> 32
            }
            if carry != 0 { out.append(UInt32(truncatingIfNeeded: carry)) }
            return BigUInt(words: out)
        }

        /// self -= other (self >= other).
        private mutating func subtract(_ other: BigUInt) {
            var borrow: UInt64 = 0
            for i in words.indices {
                let a = UInt64(words[i])
                let b = (i < other.words.count ? UInt64(other.words[i]) : 0) + borrow
                if a >= b {
                    words[i] = UInt32(truncatingIfNeeded: a - b)
                    borrow = 0
                } else {
                    words[i] = UInt32(truncatingIfNeeded: a + (UInt64(1) << 32) - b)
                    borrow = 1
                }
            }
            trim()
        }

        /// FDBigInteger.quoRemIteration: q = floor(this / S) (< 10), this = (this - q * S) * 10.
        mutating func quoRemIteration(_ s: BigUInt) -> Int {
            var q = 0
            while cmp(s) >= 0 {
                subtract(s)
                q += 1
            }
            multiply(by: 10)
            return q
        }
    }

    // MARK: FormattedFloatingDecimal (java.util.Formatter %e %f %g digits on Android)

    enum Form { case SCIENTIFIC, DECIMAL_FLOAT, GENERAL }

    struct Formatted {
        /// The mantissa characters (ASCII digits, '.', and '-' for negative input).
        var mantissa: [UInt8]
        /// The exponent characters for SCIENTIFIC (sign + at least two digits), nil otherwise.
        var exponent: [UInt8]?
        /// decExponentRounded - 1.
        var exponentRounded: Int
    }

    /// FormattedFloatingDecimal.valueOf(d, precision, form).
    static func formatted(_ d: Double, _ precisionIn: Int, _ form: Form) -> Formatted {
        var precision = precisionIn
        let fd = converter(d, isCompatibleFormat: false)
        if fd.isExceptional {
            return Formatted(mantissa: Array(fd.toJavaFormatString().utf8), exponent: nil, exponentRounded: -1)
        }
        var digits = fd.getDigits()
        let nDigits = digits.count
        let decExp = fd.getDecimalExponent()
        let isNegative = fd.isNegative
        var result = Formatted(mantissa: [], exponent: nil, exponentRounded: 0)
        let exp: Int
        switch form {
        case .DECIMAL_FLOAT:
            exp = applyPrecision(decExp, &digits, nDigits, decExp + precision)
            fillDecimal(&result, precision, digits, nDigits, exp, isNegative)
        case .SCIENTIFIC:
            exp = applyPrecision(decExp, &digits, nDigits, precision + 1)
            fillScientific(&result, precision, digits, nDigits, exp, isNegative)
        case .GENERAL:
            exp = applyPrecision(decExp, &digits, nDigits, precision)
            // adjust precision to be the number of digits to right of decimal; the real exponent to be
            // output is actually exp - 1, not exp
            if exp - 1 < -4 || exp - 1 >= precision {
                precision -= 1
                fillScientific(&result, precision, digits, nDigits, exp, isNegative)
            } else {
                precision = precision - exp
                fillDecimal(&result, precision, digits, nDigits, exp, isNegative)
            }
        }
        result.exponentRounded = exp - 1
        return result
    }

    /// Returns the exponent after rounding the digits half-up at `prec` digits.
    private static func applyPrecision(_ decExp: Int, _ digits: inout [UInt8], _ nDigits: Int, _ prec: Int) -> Int {
        if prec >= nDigits || prec < 0 {
            // no rounding necessary
            return decExp
        }
        if prec == 0 {
            // only one digit (0 or 1) is returned because the precision excludes all significant digits
            if digits[0] >= 0x35 {
                digits[0] = 0x31
                for i in 1..<Swift.max(1, nDigits) { digits[i] = 0x30 }
                return decExp + 1
            } else {
                for i in 0..<nDigits { digits[i] = 0x30 }
                return decExp
            }
        }
        var q = digits[prec]
        if q >= 0x35 {
            var i = prec
            i -= 1
            q = digits[i]
            if q == 0x39 {
                while q == 0x39 && i > 0 {
                    i -= 1
                    q = digits[i]
                }
                if q == 0x39 {
                    // carryout! High-order 1, rest 0s, larger exp.
                    digits[0] = 0x31
                    for k in 1..<Swift.max(1, nDigits) { digits[k] = 0x30 }
                    return decExp + 1
                }
            }
            digits[i] = q + 1
            for k in (i + 1)..<Swift.max(i + 1, nDigits) { digits[k] = 0x30 }
        } else {
            for k in prec..<nDigits { digits[k] = 0x30 }
        }
        return decExp
    }

    private static func fillDecimal(_ r: inout Formatted, _ precision: Int, _ digits: [UInt8], _ nDigits: Int, _ exp: Int, _ isNegative: Bool) {
        var m: [UInt8] = isNegative ? [0x2D] : []
        if exp > 0 {
            // print digits.digits.
            if nDigits < exp {
                m.append(contentsOf: digits[0..<nDigits])
                for _ in 0..<(exp - nDigits) { m.append(0x30) }
                // Do not append ".0" for formatted floats; the Formatter adds it as necessary.
            } else {
                let t = Swift.min(nDigits - exp, precision)
                m.append(contentsOf: digits[0..<exp])
                if t > 0 {
                    m.append(0x2E)
                    m.append(contentsOf: digits[exp..<(exp + t)])
                }
            }
        } else {
            let zeros = Swift.max(0, Swift.min(-exp, precision))
            let t = Swift.max(0, Swift.min(nDigits, precision + exp))
            // write '0' s before the significant digits
            if zeros > 0 {
                m.append(0x30)
                m.append(0x2E)
                for _ in 0..<zeros { m.append(0x30) }
                if t > 0 {
                    // copy only when significant digits are within the precision
                    m.append(contentsOf: digits[0..<t])
                }
            } else if t > 0 {
                m.append(0x30)
                m.append(0x2E)
                // copy only when significant digits are within the precision
                m.append(contentsOf: digits[0..<t])
            } else {
                m.append(0x30)
            }
        }
        r.mantissa = m
    }

    private static func fillScientific(_ r: inout Formatted, _ precision: Int, _ digits: [UInt8], _ nDigits: Int, _ exp: Int, _ isNegative: Bool) {
        var m: [UInt8] = isNegative ? [0x2D] : []
        let t = Swift.max(0, Swift.min(nDigits - 1, precision))
        if t > 0 {
            m.append(digits[0])
            m.append(0x2E)
            m.append(contentsOf: digits[1..<(1 + t)])
        } else {
            m.append(digits[0])
        }
        r.mantissa = m
        let expSign: UInt8
        var e: Int
        if exp <= 0 {
            expSign = 0x2D
            e = -exp + 1
        } else {
            expSign = 0x2B
            e = exp - 1
        }
        // decExponent has 1, 2, or 3, digits
        if e <= 9 {
            r.exponent = [expSign, 0x30, UInt8(e + 0x30)]
        } else if e <= 99 {
            r.exponent = [expSign, UInt8(e / 10 + 0x30), UInt8(e % 10 + 0x30)]
        } else {
            let hiExpChar = UInt8(e / 100 + 0x30)
            e %= 100
            r.exponent = [expSign, hiExpChar, UInt8(e / 10 + 0x30), UInt8(e % 10 + 0x30)]
        }
    }
}
