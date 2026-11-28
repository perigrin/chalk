my $x = 1; sub inc { ${$_[0]}++ } inc(\$x) for 1..3; print "$x\n";
