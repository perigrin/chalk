my %sig = (a => 1); my @stack = (1..3); my $top = $stack[-1]; my $str = "x" . ($top > 2 ? "big" : "small") . (exists $sig{a} ? "!" : "?"); my $c = () = $str =~ /[a-z]/g; print "$str$c\n";
