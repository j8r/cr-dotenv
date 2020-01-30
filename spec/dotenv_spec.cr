require "spec"
require "../src/dotenv"

Spec.before_each do
  ENV.clear
end

def expect_invalid_char(string : String, message : String, file = __FILE__, line = __LINE__)
  ex = expect_raises(Dotenv::ParseError, file: file, line: line) do
    Dotenv.load_string string
  end
  ex.to_s.should eq "Parse error on line: `#{string}`"
  ex.cause.to_s.should eq message
end

describe Dotenv do
  describe ".parse" do
    it "from String" do
      hash = Dotenv.parse "VAR=Hello"
      hash.should eq({"VAR" => "Hello"})
    end

    it "from IO" do
      io = IO::Memory.new "VAR=Hello"
      hash = Dotenv.parse io
      hash.should eq({"VAR" => "Hello"})
    end
  end

  describe ".load_string" do
    describe "simple quoted value" do
      it "reads with whitespaces" do
        hash = Dotenv.load_string "VAR=' value '"
        hash["VAR"].should eq " value "
      end

      it "reads one with double quotes" do
        hash = Dotenv.load_string %(VAR='"value"')
        hash["VAR"].should eq %("value")
      end

      it "reads one including simple quotes" do
        hash = Dotenv.load_string "VAR='va'lue'"
        hash["VAR"].should eq "va'lue"
      end
    end

    describe "double quoted value" do
      it "reads with whitespaces" do
        hash = Dotenv.load_string %(VAR=" value ")
        hash["VAR"].should eq %( value )
      end

      it "reads one with simple quotes" do
        hash = Dotenv.load_string %(VAR="'value'")
        hash["VAR"].should eq %('value')
      end

      it "reads one including double quotes" do
        hash = Dotenv.load_string %(VAR="va"l"ue")
        hash["VAR"].should eq %(va"l"ue)
      end
    end

    it "raises on space in an unquoted value" do
      expect_invalid_char "VAR=v al", "An unquoted value cannot contain a whitespace: ' '"
    end

    it "raises on space before a variable value" do
      expect_invalid_char "VAR= val", "A value cannot start with a whitespace: ' '"
    end

    it "raises on invalid characters inside a variable key" do
      {'#', '"', '\''}.each do |char|
        expect_invalid_char "V#{char}AR=val", "A variable key cannot contain #{char.inspect}"
      end
    end

    it "strips whitespaces" do
      Dotenv.load_string "  VAR=Hello \t\r "
      ENV["VAR"].should eq "Hello"
    end

    it "does not override existing var" do
      ENV["VAR"] = "existing"
      Dotenv.load_string "VAR=Hello"
      ENV["VAR"].should eq "existing"
    end

    it "ignores commented lines" do
      hash = Dotenv.load_string <<-DOTENV
      # This is a comment
      VAR=Dude
      DOTENV
      hash.should eq({"VAR" => "Dude"})
    end

    it "ingores empty lines" do
      hash = Dotenv.load_string <<-DOTENV

      VAR=Dude

      DOTENV
      hash.should eq({"VAR" => "Dude"})
    end

    it "reads allowed `=` in values" do
      hash = Dotenv.load_string "VAR=postgres://foo@localhost:5432/bar?max_pool_size=10"
      hash.should eq({"VAR" => "postgres://foo@localhost:5432/bar?max_pool_size=10"})
    end

    it "reads valid lines only" do
      Dotenv.load_string "VAR1=Hello\nHELLO:asd"
      ENV["VAR1"].should eq "Hello"
      ENV["HELLO"]?.should be_nil
    end

    it "loads a string, and overrides duplicate keys" do
      ENV["VAR"] = "Hello"
      Dotenv.load_string "VAR=World", override_keys: true
      ENV["VAR"].should eq "World"
    end
  end

  describe ".load?" do
    it "returns nil on missing file" do
      Dotenv.load?(".some-non-existent-env-file").should be_nil
    end

    it "loads environment variables from a file" do
      tempfile = File.tempfile "dotenv", &.print("VAR=Hello")
      begin
        Dotenv.load? tempfile.path
        ENV["VAR"].should eq "Hello"
      ensure
        tempfile.delete
      end
    end

    it "loads environment variables from a file, and overrides duplicate keys" do
      tempfile = File.tempfile "dotenv", &.print("VAR=Hello")
      begin
        ENV["VAR"] = "World"
        Dotenv.load? tempfile.path, override_keys: true
        ENV["VAR"].should eq "Hello"
      ensure
        tempfile.delete
      end
    end
  end

  describe ".load" do
    context "From file" do
      it "raises on missing file" do
        expect_raises(Errno) do
          Dotenv.load ".some-non-existent-env-file"
        end
      end

      it "loads environment variables" do
        tempfile = File.tempfile "dotenv", &.print("VAR=Hello")
        begin
          Dotenv.load tempfile.path
          ENV["VAR"].should eq "Hello"
        ensure
          tempfile.delete
        end
      end

      it "loads environment variables, and overrides duplicate keys" do
        tempfile = File.tempfile "dotenv", &.print("VAR=Hello")
        begin
          ENV["VAR"] = "World"
          Dotenv.load tempfile.path, override_keys: true
          ENV["VAR"].should eq "Hello"
        ensure
          tempfile.delete
        end
      end
    end

    context "from IO" do
      it "loads environment variables" do
        io = IO::Memory.new "VAR2=test\nVAR3=other"
        hash = Dotenv.load io
        hash["VAR2"].should eq "test"
        hash["VAR3"].should eq "other"
        ENV["VAR2"].should eq "test"
        ENV["VAR3"].should eq "other"
      end

      it "loads environment variables, and overrides duplicate keys" do
        io1 = IO::Memory.new "VAR2=test\nVAR3=other"
        io2 = IO::Memory.new "VAR2=other\nVAR3=test"
        Dotenv.load io1
        ENV["VAR2"].should eq "test"
        ENV["VAR3"].should eq "other"
        Dotenv.load io2, override_keys: true
        ENV["VAR2"].should eq "other"
        ENV["VAR3"].should eq "test"
      end
    end

    context "from Hash" do
      it "loads environment variables" do
        hash = Dotenv.load({"test" => "test"})
        hash["test"].should eq "test"
        ENV["test"].should eq "test"
      end

      it "loads environment variables, and overrides duplicate keys" do
        Dotenv.load({"test" => "test"})
        ENV["test"].should eq "test"
        Dotenv.load({"test" => "updated"}, override_keys: true)
        ENV["test"].should eq "updated"
      end
    end
  end
end
