my $s = "aXbXc"; my $n = () = $s =~ /X/g; my @m = $s =~ /(\w)X/g; my $c = 0; $c++ while $s =~ /X/g; print "$n@m$c\n";
