require "date"
require "time"

# Shared input contract for the API and the local dashboard.
class AnalyticsFilters
  class Invalid < StandardError; end

  MAX_RANGE_SECONDS = 90 * 24 * 60 * 60
  TIMESTAMP = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z/
  PLATFORMS = %w[web ios android unknown].freeze
  # ISO 3166-1 alpha-2 plus the approved unknown sentinel. No network lookup.
  COUNTRIES = %w[
    AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE
    BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD
    CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM
    DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF
    GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU
    ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN
    KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME
    MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA
    NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM
    PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI
    SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK
    TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI
    VN VU WF WS YE YT ZA ZM ZW
  ].freeze

  ABSENT = Object.new.freeze

  attr_reader :from, :to, :name, :platform, :country

  def initialize(from: nil, to: nil, name: ABSENT, platform: ABSENT, country: ABSENT)
    @from = parse_timestamp(from, "from")
    @to = parse_timestamp(to, "to")
    unless @from < @to && @to.to_r - @from.to_r <= MAX_RANGE_SECONDS
      raise Invalid, "Range must be positive and at most 90 days"
    end

    unless name.equal?(ABSENT) || (name.is_a?(String) && name.valid_encoding? && name.bytesize <= 128 && !name.strip.empty?)
      raise Invalid, "Invalid name filter"
    end
    unless platform.equal?(ABSENT) || PLATFORMS.include?(platform)
      raise Invalid, "Invalid platform filter"
    end
    unless country.equal?(ABSENT) || COUNTRIES.include?(country) || country == "unknown"
      raise Invalid, "Invalid country filter"
    end

    @name = name unless name.equal?(ABSENT)
    @platform = platform unless platform.equal?(ABSENT)
    @country = country unless country.equal?(ABSENT)
  end

  # Stored timestamps are discrete milliseconds. Ceil both bounds to preserve
  # exact [from,to) membership even when an input has sub-millisecond precision.
  def from_milliseconds
    millisecond_ceiling(from)
  end

  def to_milliseconds
    millisecond_ceiling(to)
  end

  def dates
    last_date = to.to_date
    last_date -= 1 if to.hour.zero? && to.min.zero? && to.sec.zero? && to.subsec.zero?
    from.to_date..last_date
  end

  private

  def parse_timestamp(value, field)
    match = TIMESTAMP.match(value) if value.is_a?(String) && value.ascii_only?
    if match && Date.valid_date?(*match.captures.first(3).map(&:to_i)) &&
        match[4].to_i < 24 && match[5].to_i < 60 && match[6].to_i < 60
      time = Time.iso8601(value).utc
      return time if time.year.between?(1900, 2299) && millisecond_ceiling(time).year <= 2299
    end
    raise Invalid, "Invalid #{field} timestamp"
  rescue ArgumentError
    raise Invalid, "Invalid #{field} timestamp", cause: nil
  end

  def millisecond_ceiling(time)
    Time.at(Rational((time.to_r * 1000).ceil, 1000)).utc
  end
end
