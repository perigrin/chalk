sub w { my $s = $_[0]; $s = "(" . $s; $s = "$s$_[0])"; $s } print w("a"), "\n";
