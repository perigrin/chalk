sub f { (4, 5, 6) } my $c = f(); my $n = () = f(); my @s = (f())[0, 1]; print "$c$n@s\n";
