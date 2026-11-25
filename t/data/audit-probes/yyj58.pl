$_ = "keep"; my $n = () = "abc" =~ /./g; print "$_$n\n"; for my $w (qw(a)) { $_ .= "!" } print "$_\n";
