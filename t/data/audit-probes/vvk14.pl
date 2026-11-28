sub f { return unless @_; "a" } my @l = f(); my $s = f(); print scalar(@l), defined $s ? "d" : "u", "\n";
