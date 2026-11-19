my $str = "a1b2"; my $cnt = () = $str =~ /\d/g; my $c2 = ($str =~ s/\d//g); print "$cnt $c2 $str\n";
