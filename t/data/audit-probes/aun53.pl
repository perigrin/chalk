my $d=@ARGV; my $q = eval { 1 / $d } // "died"; print "$q\n";
