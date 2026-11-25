my $v=0; for (1..3) { $v=[$v] } print ref($v), ref($v->[0]), ref($v->[0][0]), $v->[0][0][0], "\n";
