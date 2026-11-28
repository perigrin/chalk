my $s = "hello world"; my $c = () = $s =~ /o/g; my $t = ($s =~ tr/o//); (my $u = $s) =~ s/o/0/g; print "$c$t$u\n";
