eval { my $z = 0; my $v = 1 / $z; }; print $@ =~ /division by zero/ ? "div" : "no", "\n";
