my $r = print ""; my $p = printf("%s", ""); print $r, $p, "\n"; print STDOUT "out\n"; print {*STDOUT} "glob\n"; printf STDOUT "%s-%s\n", "a", "b"; printf("%d%%\n", 50);
