sub ctx { return (4,5,6) } my $c = () = ctx(); my $last = (ctx())[-1]; print "$c $last\n";
