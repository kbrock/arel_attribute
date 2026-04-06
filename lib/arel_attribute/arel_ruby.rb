# frozen_string_literal: true

module ArelAttribute
  # Converts an arel expression into a Ruby source string.
  #
  # The generated code assumes `self` is the ActiveRecord instance,
  # so it can be used directly inside a method body via module_eval.
  #
  # Supports single-row, single-table value expressions:
  #   COALESCE, UPPER, LOWER, CONCAT, CAST,
  #   math (+, -, *, /), CASE/WHEN, comparisons,
  #   IS NULL, AND, OR, NOT, grouping, literals.
  #
  # Raises UnsupportedNode for anything it can't translate
  # (subqueries, aggregates, etc.) — callers should define Ruby manually.
  module ArelRuby
    class UnsupportedNode < ArelAttribute::Error; end

    # Convert an arel node into a Ruby source string.
    #
    # The returned string is valid Ruby that can be placed inside a method body.
    # Column references become `self[:col]` for real columns or `col_name` for
    # virtual attributes (calling the Ruby getter).
    #
    # @param node [Arel::Nodes::Node] the arel expression
    # @param klass [Class] the ActiveRecord model class (for resolving virtual attributes)
    # @return [String] Ruby source
    def self.convert(node, klass)
      case node

      # Column reference: t[:name]
      when Arel::Attributes::Attribute
        attr_name = node.name.to_s
        if klass.respond_to?(:arel_attribute?) && klass.arel_attribute?(attr_name)
          # virtual attribute — call the ruby getter
          attr_name
        else
          # real column
          "self[:#{attr_name}]"
        end

      # Our custom node — unwrap to the inner expression
      when Arel::Nodes::ArelAttribute
        convert(node.expr, klass)

      # Grouping (parentheses) — pass through
      when Arel::Nodes::Grouping
        "(#{convert(node.expr, klass)})"

      # Named functions: UPPER, LOWER, COALESCE, CONCAT, LENGTH, REPLACE, etc.
      when Arel::Nodes::NamedFunction
        convert_function(node, klass)

      # Math: +, -, *, /
      when Arel::Nodes::Addition
        "#{convert(node.left, klass)} + #{convert(node.right, klass)}"
      when Arel::Nodes::Subtraction
        "#{convert(node.left, klass)} - #{convert(node.right, klass)}"
      when Arel::Nodes::Multiplication
        "#{convert(node.left, klass)} * #{convert(node.right, klass)}"
      when Arel::Nodes::Division
        "#{convert(node.left, klass)} / #{convert(node.right, klass)}"

      # String concatenation (||)
      when Arel::Nodes::Concat
        "#{convert(node.left, klass)}.to_s + #{convert(node.right, klass)}.to_s"

      # CASE/WHEN
      when Arel::Nodes::Case
        convert_case(node, klass)

      # Comparisons (used inside CASE conditions)
      when Arel::Nodes::Equality
        if node.right.nil? || (node.right.respond_to?(:nil?) && node.right.nil?)
          "#{convert(node.left, klass)}.nil?"
        else
          "#{convert(node.left, klass)} == #{convert(node.right, klass)}"
        end
      when Arel::Nodes::NotEqual
        if node.right.nil? || (node.right.respond_to?(:nil?) && node.right.nil?)
          "!#{convert(node.left, klass)}.nil?"
        else
          "#{convert(node.left, klass)} != #{convert(node.right, klass)}"
        end
      when Arel::Nodes::GreaterThan
        "#{convert(node.left, klass)} > #{convert(node.right, klass)}"
      when Arel::Nodes::LessThan
        "#{convert(node.left, klass)} < #{convert(node.right, klass)}"
      when Arel::Nodes::GreaterThanOrEqual
        "#{convert(node.left, klass)} >= #{convert(node.right, klass)}"
      when Arel::Nodes::LessThanOrEqual
        "#{convert(node.left, klass)} <= #{convert(node.right, klass)}"

      # Logical operators
      when Arel::Nodes::And
        node.children.map { |c| convert(c, klass) }.join(" && ")
      when Arel::Nodes::Or
        node.children.map { |c| convert(c, klass) }.join(" || ")
      when Arel::Nodes::Not
        "!#{convert(node.expr, klass)}"

      # Literal values
      when Arel::Nodes::Quoted
        node.value.inspect
      when Arel::Nodes::Casted
        node.value.inspect
      when Arel::Nodes::SqlLiteral
        convert_sql_literal(node)

      # Raw Ruby values (arel allows bare integers in expressions like `col * 1048576`)
      when Numeric
        node.inspect
      when String
        node.inspect
      when Symbol
        node.to_s.inspect
      when NilClass
        "nil"
      when TrueClass, FalseClass
        node.inspect

      else
        raise UnsupportedNode, "Cannot convert #{node.class} to Ruby: #{node.inspect}"
      end
    end

    # @private
    def self.convert_function(node, klass)
      args = node.expressions
      case node.name.upcase
      when "COALESCE"
        parts = args.map { |a| convert(a, klass) }
        parts.join(" || ") # Ruby || returns first truthy — same as COALESCE for non-false values
      when "UPPER"
        "#{convert(args.first, klass)}&.upcase"
      when "LOWER"
        "#{convert(args.first, klass)}&.downcase"
      when "LENGTH"
        "#{convert(args.first, klass)}&.length"
      when "REPLACE"
        "#{convert(args[0], klass)}&.gsub(#{convert(args[1], klass)}, #{convert(args[2], klass)})"
      when "CONCAT"
        args.map { |a| "#{convert(a, klass)}.to_s" }.join(" + ")
      when "SUBSTR", "SUBSTRING"
        convert_substr(args, klass)
      when "TRIM"
        "#{convert(args.first, klass)}&.strip"
      when "LTRIM"
        "#{convert(args.first, klass)}&.lstrip"
      when "RTRIM"
        convert_rtrim(args, klass)
      when "INSTR"
        # INSTR(string, substring) returns position (1-based) or 0
        "((pos = #{convert(args[0], klass)}&.index(#{convert(args[1], klass)})) ? pos + 1 : 0)"
      when "STRPOS"
        # PostgreSQL STRPOS — same semantics as INSTR
        "((pos = #{convert(args[0], klass)}&.index(#{convert(args[1], klass)})) ? pos + 1 : 0)"
      when "CAST"
        convert_cast(args.first, klass)
      when "ABS"
        "#{convert(args.first, klass)}&.abs"
      else
        raise UnsupportedNode, "Unknown SQL function #{node.name}: #{node.inspect}"
      end
    end

    # @private
    def self.convert_substr(args, klass)
      str = convert(args[0], klass)
      # SQL SUBSTR is 1-based, Ruby is 0-based
      start_expr = convert(args[1], klass)
      if args[2]
        len = convert(args[2], klass)
        "#{str}&.slice((#{start_expr}) - 1, #{len})"
      else
        "#{str}&.slice((#{start_expr}) - 1..)"
      end
    end

    # @private
    def self.convert_rtrim(args, klass)
      if args.size == 1
        "#{convert(args.first, klass)}&.rstrip"
      else
        # RTRIM(str, chars) — strip trailing characters
        "#{convert(args[0], klass)}&.chomp(#{convert(args[1], klass)})"
      end
    end

    # @private — CAST(expr AS type) is represented as NamedFunction("CAST", [expr.as("type")])
    def self.convert_cast(node, klass)
      # The argument to CAST is typically an As node: expr AS type_name
      if node.is_a?(Arel::Nodes::As)
        expr = convert(node.left, klass)
        type_name = node.right.to_s.downcase
        case type_name
        when "integer", "unsigned", "signed", "bigint"
          "#{expr}&.to_i"
        when "float", "real", "double", "decimal", "numeric"
          "#{expr}&.to_f"
        when /char|text|string/
          "#{expr}&.to_s"
        else
          raise UnsupportedNode, "Unknown CAST type: #{type_name}"
        end
      else
        convert(node, klass)
      end
    end

    # @private
    def self.convert_case(node, klass)
      parts = []
      parts << if node.case
        # Simple CASE: CASE expr WHEN val THEN result ...
        "case #{convert(node.case, klass)}"
      else
        # Searched CASE: CASE WHEN condition THEN result ...
        "case"
      end
      node.conditions.each do |cond|
        parts << "when #{convert(cond.left, klass)} then #{convert(cond.right, klass)}"
      end
      if node.default
        parts << "else #{convert(node.default.expr, klass)}"
      end
      parts << "end"
      "(#{parts.join("; ")})"
    end

    # @private — SQL string literals like Arel.sql("'value'") need unwrapping
    def self.convert_sql_literal(node)
      str = node.to_s
      # Common pattern: Arel.sql("'some_string'") — unwrap the SQL quotes
      if str.match?(/\A'(.*)'\z/)
        str[1..-2].inspect
      elsif str == "NULL"
        "nil"
      elsif str.match?(/\A-?\d+(\.\d+)?\z/)
        str
      else
        raise UnsupportedNode, "Cannot convert SQL literal to Ruby: #{str.inspect}"
      end
    end

    private_class_method :convert_function, :convert_substr, :convert_rtrim,
      :convert_cast, :convert_case, :convert_sql_literal
  end
end
