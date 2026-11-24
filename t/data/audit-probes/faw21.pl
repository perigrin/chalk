our %h; my $c=0; sub add { $h{$_[0]}=1 } $c++ if %h; add("a"); $c+=10 if %h; print "$c\n";
