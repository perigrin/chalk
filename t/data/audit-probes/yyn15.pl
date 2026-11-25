eval { my $x = 1; my $y = 0; my $z = $x / $y; }; print $@ =~ /^Illegal division by zero/ ? "div" : "other", "\n";
