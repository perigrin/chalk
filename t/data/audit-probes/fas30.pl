our %g=(a=>1); sub n { $g{b}=2; 0 } my $c = keys(%g) + n() + keys(%g); print "$c\n";
