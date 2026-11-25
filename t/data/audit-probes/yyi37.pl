sub trim { s/^\s+|\s+$//g for @_ } my $s=" a "; my @l=(" b "," c"); trim($s, @l); print "[$s][@l]\n";
