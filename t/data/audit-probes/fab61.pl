my @r = map { my $x=$_; grep { $_ > $x } 1..3 } 1..2; print "@r\n";
