our $g=1; my @r=(\$g); { local $g=5; ${$r[0]}++ } print "$g\n";
