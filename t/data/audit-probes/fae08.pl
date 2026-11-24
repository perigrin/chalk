my $z=0; my $s = eval { 1/$z }; print defined $s ? 1 : 0, $@ =~ /division/ ? "d" : "n", "\n";
