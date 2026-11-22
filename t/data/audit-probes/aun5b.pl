my $d=@ARGV; sub q { 1/$_[0] } my $r = $d ? q($d) : "z"; print "$r\n";
