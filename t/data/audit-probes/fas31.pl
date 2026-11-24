my @g=(1); sub n { push @g,2; 0 } my $c = @g + n() + @g; print "$c\n";
