eval { my $z = 0; my $v = 5 % $z; }; print $@ =~ /zero/ ? "mod" : "no", "\n";
