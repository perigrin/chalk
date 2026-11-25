our $g=0; for (1..3) { local $g=$_; last if $_==2 } print "$g\n";
