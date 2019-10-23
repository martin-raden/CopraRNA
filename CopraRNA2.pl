#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Cwd 'abs_path';

my $COPRARNA_VERSION="2.1.3";

 # License: MIT

 # When using CopraRNA please cite:
 # Patrick R. Wright, et al. 
 # Comparative genomics boosts target prediction for bacterial small RNAs
 # Proc Natl Acad Sci USA, 2013, 110 (37), E3487–E3496.

 # and/or

 # Patrick R. Wright, et al.
 # CopraRNA and IntaRNA: predicting small RNA targets, networks and interaction domains
 # Nucleic Acids Research, 2014, 42 (W1), W119-W123.

 # If you run into problems or have questions, please do not hesitate to
 # contact us.
 # rna@informatik.uni-freiburg.de

 #    Comparative prediction algorithm for sRNA targets (CopraRNA)
 #
 #    Contributions by: 
 #
 #    Patrick R. Wright              
 #    Jens Georg
 #    Martin Raden, nee Mann
 #    Rolf Backofen
 #    Steffen C. Lott
 #    Andreas S. Richter 
 #    Florian Eggenhofer
 #    Robert Kleinkauf
 #    Dragos A. Sorescu
 #    Wolfgang R. Hess
 #    Stephan Klaehn
 #    Joerg Vogel
 #    Kai Papenfort

#####################################################

#### dependencies: see file CopraRNA2-deps.yml

#####################################################

#### changelog

# v2.1.3   : input sRNA file is kept, updated organisms-list
#
# v2.1.2   : added R downstream ooi false positive removal
#
# v2.1.1   : added input exceptions
#            DAVID python code now py2 and py3 compatible
#            changed coloring in evolutionary heatmap
#            fixed issue for regions plots for sequences with non ATGC alphabet
#
# v2.1.0   : topcount default 200
#            stopped tracking edits manually
#
# v2.0.6   : new p-value combination (no hard cutoff anymore // switching to integrated superior method) 
#            standard root function for weights is now 1 instead of 2.5 (no more weight reduction)
#            added phylogeny output directory in clean output
#            -cop2 option is now -cop1 since CopraRNA2 will be standard
#            removed -pvcut option
#            added -nooi option
#            added gawk, sed, grep, tr, sort as dependencies
#            added extended regions plots
#            aux enrichment now also done for count specified by $enrich
#            adding consensus prediction
#            removed phantomjs bin // now installing it via conda
#
# v2.0.5.1 : major restructuring due to changed IntaRNA version (2.0.4)
#            added IntaRNA --tAccW and --tAccL as parameters to CopraRNA 
#            adjusted update_kegg2refseq for new format of prokaryotes.txt
#            added verbose terminal printing option
#            added topcount option
#            added pvalue cutoff option for CopraRNA 2
#            now using Cwd 'abs_path' to make script path locations dynamic
#            added warning for run directories that contain many files
#            added websrv option to only output websrv files if explicitly called for
#            added root option // applies this root function to weights both for CopraRNA1 and CopraRNA2 pvalue combination
#            now calculating normalized IntaRNA energy scores internally in IntaRNA // adjusted CopraRNA accordingly
#            added enrichment parameter 
#            added noclean parameter
#
# v2.0.5   : changed to using IntaRNA2.0 ui
#            local mirror for .gbk changed to .gb because file ending in local mirror changed
#            removed evir dependency by now sourcing the gev and pgev functions locally
#            added MIT license
# v2.0.4.2 : now using Hartung.R to combine pvalues // no previous calculation of rho needed
# v2.0.4.1 : added new adjust_tags_clustered.R that now makes two files one for pold one for padj // also added rho calculation rho_script.R
#            changed scale_clusters.pl to combine_clusters.pl // reimplementation
#            weights are no longer subjected to the 2.5th root (only for CopraRNA2)
# v2.0.4   : major changes to the code preparing for CopraRNA2 benchmarking and publication (UPGMA tree for example)
# v2.0.3.2 : fixed issue with RefSeq IDs longer than 11 that chars caused job fail // changed DAVID parameters to "medium" from the webpage
#            mirroring DAVID v6.7 specifically instead of DAVID v6.8
# v2.0.3.1 : changed DAVID-WS from perl to python client
# v2.0.3   : using local mirrors of old NCBI ID system for compatibility if available
# v2.0.2   : support of new NCBI ID system
# v2.0.1   : Iterative organism subset analysis enabled. Auxiliary enrichment output added. Minimal relative cluster size parameter added. IntaRNA parameters changed to -w 150 -L 100
# v1.3.0   : Potential outlier detection; evolutionary tree visualization; minor bugfix in weight calculation.
# v1.2.9   : Now using (Benjamini&Hochberg, 1995) for false discovery rate (fdr) estimation. Fixed issue where trees with branch lengths of zero would cause job failures.
# v1.2.8   : Fixed the issue where jobs with input organisms with exactly the same 16S sequences would fail
# v1.2.7   : Reimplementation of p-value joining (runtime reduction); Minor bugfix for heatmap drawing and regions plots
# v1.2.6   : Added heatmap pdf output
# v1.2.5   : Added functional enrichment heatmaps
# v1.2.4   : Changed DomClust parameters to standard MBGD parameters
# v1.2.3   : BLAST speedup
# v1.2.2   : Fixed issue with organism: 'sfd'
# v1.2.1   : RefSeq files now being downloaded from NCBI FTP

my $help = "";
my $sRNAs_fasta = "input_sRNA.fa";
my $upstream = 200;
my $downstream = 100;
my $region = "5utr";
my $RelClusterSize = 0.5;
my $core_count = 1; # how many parallel processes are allowed
my $winsize = 150; # IntaRNA window size
my $maxbpdist = 100; # IntaRNA maximum base pair distance 
my $cop1 = 0;
my $cons = 0;
my $nooi = 0; # if this is set to 1 then the standard prediction mode is CopraRNA 2 balanced else ooi
my $verbose = 0;
my $noclean = 0;
my $websrv = 0;
my $ooi_filt = 0; ## for copraRNA2_ooi_post_filtering.R
my $pvalcutoff = 0.15; # p-value cutoff for CopraRNA 2 //
my $topcount = 200; # amount of top predictions //
my $root = 1; # root function to apply to the weights //
my $enrich = 0; ## functional enrichment needs to be specifically turned on 
                ## this option also allows to specify how many top predictions to use for the enrichment
my $genomePath = "."; # where to look for and store genome files
my $temperature = 37; # temperature for prediction

# get absolute path
my $ABS_PATH = abs_path($0);
# remove script name at the end
# match all non slash characters at the end of the string
$ABS_PATH =~ s|[^/]+$||g;
my $PATH_COPRA = $ABS_PATH; 

GetOptions (
    'help|?'		=> \$help,
    'srnaseq:s'		=> \$sRNAs_fasta,
    'ntup:i'		=> \$upstream,
    'ntdown:i'		=> \$downstream,
    'cores:i'		=> \$core_count,
    'region:s'		=> \$region, # one of "5utr", "3utr", "cds"
    'rcsize:f'		=> \$RelClusterSize,
    'winsize:i'		=> \$winsize,
    'maxbpdist:i'	=> \$maxbpdist,
    'cop1'		=> \$cop1, # switch for coprarna1, if set then coprarna1 is run // else only coprarna2
    'verbose'		=> \$verbose, # switch for verbose output during computation
    'websrv'		=> \$websrv, # switch for providing webserver output
    'noclean'		=> \$noclean, # switch to prevent cleaning of files
    'nooi'		=> \$nooi, # switch to set prediction mode to balanced mode
    'topcount:i'	=> \$topcount, # amount of top predictions to return
    'enrich:i'		=> \$enrich, # functional enrichment needs to be specifically turned on // also how many top preds to use for enrichment 
    'root:i'		=> \$root, # root function to apply to the weights
    'cons:i'		=> \$cons, # consensus mode / 0=off, 1=ooi_cons, 2=overall_cons
    'ooifilt:f'		=> \$ooi_filt, # for copraRNA2_ooi_post_filtering.R
    'temperature:f'		=> \$temperature,
    'genomePath:s'		=> \$genomePath,
);

if ($help) {

print "\nCopraRNA ".$COPRARNA_VERSION."\n\n",

"CopraRNA is a tool for sRNA target prediction. It computes whole genome target predictions\n",
"by combination of distinct whole genome IntaRNA predictions. As input CopraRNA requires\n",
"at least 3 homologous sRNA sequences from 3 distinct organisms in FASTA format.\n", 
"Furthermore, each organisms' genome has to be part of the NCBI Reference Sequence (RefSeq)\n",
"database (i.e. it should have exactly this NZ_* or this NC_XXXXXX format where * stands\n",
"for any character and X stands for a digit between 0 and 9). Depending on sequence length\n",
"(target and sRNA), amount of input organisms and genome sizes, CopraRNA can take up to 24h\n",
"or longer to compute. In most cases it is significantly faster. It is suggested to run CopraRNA\n", 
"on a machine with at least 8 GB of memory.\n\n",
 
"CopraRNA produces a lot of file I/O. It is suggested to run CopraRNA in a dedicated\n",
"empty directory to avoid unexpected behavior.\n\n",

"The central result table is CopraRNA_result.csv. Further explanations concerning the files\n",
"in the run directory can be found in README.txt.\n\n",

"The following options are available:\n\n",
" --help                    this help\n\n",
" --srnaseq                 FASTA file with small RNA sequences (def:input_sRNA.fa)\n",
" --region                  region to scan in whole genome target prediction (def:5utr)\n",
"                           '5utr' for start codon\n",
"                           '3utr' for stop codon\n",
"                           'cds' for entire transcript\n",
" --ntup                    amount of nucleotides upstream of '--region' to parse for targeting (def:200)\n",
" --ntdown                  amount of nucleotides downstream of '--region' to parse for targeting (def:100)\n",
" --cores                   amount of cores to use for parallel computation (def:1)\n",
" --rcsize                  minimum amount (%) of putative target homologs that need to be available \n",
"                           for a target cluster to be considered in the CopraRNA1 part (see --cop1) of the prediction (def:0.5)\n",
" --winsize                 IntaRNA target (--tAccW) window size parameter (def:150)\n",
" --maxbpdist               IntaRNA target (--tAccL) maximum base pair distance parameter (def:100)\n",
" --cop1                    switch for CopraRNA1 prediction (def:off)\n",
" --cons                    controls consensus prediction (def:0)\n",
"                           '0' for off\n",
"                           '1' for organism of interest based consensus\n",
"                           '2' for overall consensus based prediction\n",
" --verbose                 switch to print verbose output to terminal during computation (def:off)\n",
" --websrv                  switch to provide webserver output files (def:off)\n",
" --noclean                 switch to prevent removal of temporary files (def:off)\n",
" --enrich                  if entered then DAVID-WS functional enrichment is calculated with given amount of top predictions (def:off)\n",
" --nooi                    if set then the CopraRNA2 prediction mode is set not to focus on the organism of interest (def:off)\n",
" --ooifilt                 post processing filter for organism of interest p-value 0=off (def:0)\n",
" --root                    specifies root function to apply to the weights (def:1)\n",
" --topcount                specifies the amount of top predictions to return and use for the extended regions plots (def:200)\n",
" --genomePath              path where NCBI genome files (*.gb) are to be stored (def:"." == working directory)\n\n",
" --temperature             temperature in Celsius to be used for interaction prediction (def:37.0)\n\n",
"\n",
"Example call: CopraRNA2.pl -srnaseq sRNAs.fa -ntup 200 -ntdown 100 -region 5utr -enrich 200 -topcount 200 -cores 4\n\n",
"License: MIT\n\n",
"References: \n",
"1. Wright PR et al., Comparative genomics boosts target prediction for bacterial small RNAs\n   Proc Natl Acad Sci USA, 2013, 110 (37), E3487–E3496\n",
"2. Wright PR et al., CopraRNA and IntaRNA: predicting small RNA targets, networks and interaction domains\n   Nucleic Acids Research, 2014, 42 (W1), W119-W123\n",
"\n";

exit(0);

}

# input check
unless (-e $sRNAs_fasta) {
    die("\nError: No input FASTA supplied!\nUse '-h' option for help.\n\n");
}

# create genome path if necessary
(system("mkdir -p $genomePath") == 0) or die("\nError: could not create genome path '$genomePath'.\n\n");

# rudimentary check for fasta
my $check_fa = `grep '>' $sRNAs_fasta`;
chomp $check_fa;
die("\nError: The input file ($sRNAs_fasta) supplied does not appear to be a FASTA file!\n\n") unless($check_fa);

# check for sequence count in input being more than 2
my $count_fa = `grep -c '>' $sRNAs_fasta`;
chomp $count_fa;
die("\nError: The input file ($sRNAs_fasta) seems to contain less than 3 sequences!\n\n") unless($count_fa>2);

# check for ooifilt <=1 and >= 0
die("\nError: ooifilt needs to be specified between 0 and 1. You set $ooi_filt\n\n") unless ($ooi_filt>=0 and $ooi_filt<=1);

# create warning for non empty run dir
my @dir_files = <*>;
my $file_count = scalar(@dir_files);
print "\nWarning: your run directory contains many files ($file_count). In general it is suggested to run CopraRNA in an empty directory to avoid unexpected behaviour.\n\n" if ($file_count > 10);

# check core count // if wrong set it to 1 //
if ($core_count <= 1) {
    $core_count = 1;
}

# check region parameter
die ("\nError: -region parameter must be one of 5utr, 3utr or cds. You set '$region'.\n\n") unless ($region eq "5utr" or $region eq "3utr" or $region eq "cds");

# check cons paramter
die ("\nError: -cons parameter must be one of 0, 1 or 2. You set '$cons'.\n\n") unless ($cons eq 2 or $cons eq 1 or $cons eq 0);

# disallow nooi=1 and cons=1 combination
die ("\nError: -cons 1 can not be combined with -nooi 1. Set -cons to 0 or 2.\n\n") if ( ($cons eq 1) and $nooi );

# disallow consensus predictions with coprarna 1
die ("\nError: -cons must be 0 for -cop1 prediction. You set '$cons'.\n\n") if ( ( ($cons eq 1) and $cop1 ) or ( ($cons eq 2) and $cop1 ) );

# check for gaps
system "grep '-' $sRNAs_fasta > find_gaps.txt";
if (-s "find_gaps.txt") { die("\nError: Gaps are present in sRNA sequences. Please delete them from the file and restart.\n\n"); }

# check for correct RefSeq formatted headers and their presence in the availibility table
my $headerIDs = `grep ">" $sRNAs_fasta | sed 's/>//g' | tr '\n' ';'`;
chop $headerIDs;
my @splitHeaderIDs = split(/;/,$headerIDs);
foreach(@splitHeaderIDs) {
    die("\nError: $_ does not match correct RefSeq ID format (NZ_* or NC_XXXXXX where * stands for any character and X stands for a digit between 0 and 9).\n\n") unless ($_ =~ m/NC_\d{6}|NZ_.*/);
    $_ =~ s/^\s+|\s+$//g; 
    my $availabilityCheck = `grep '$_' $PATH_COPRA/coprarna_aux/kegg2refseqnew.csv`;
    die("\nError: '$_' is not present in the availability list and is thus not compatible with CopraRNA.\n\n") unless (length $availabilityCheck); 
}

# check that maxbpdist ist smaller or equal to windowsize
die("\nError: The maximal basepair distance ($maxbpdist) is larger than the given window size ($winsize) but must be <= to the windows size. Please change the parameters accordingly.\n\n") if ($maxbpdist > $winsize);

# check for ntup + ntdown being >= $winsize because of IntaRNA parameters
my $sumUpDown = $upstream+$downstream;
if ($region eq "5utr" or $region eq "3utr") {
    die("\nError: (-ntup + -ntdown) is $sumUpDown but must be >= $winsize (--winsize). Please change the parameters accordingly.\n\n") if ( $sumUpDown < $winsize );
}

# check for correct range of 0.5 <= -rcsize <= 1.0
die("\nError: -rcsize can only be specified between 0 and 1.0. You set '$RelClusterSize'.\n\n") unless ($RelClusterSize >= 0 and $RelClusterSize <= 1.0);

# check for duplicate IDs in FASTA header // not allowed
my $duplicate_fasta_header = `grep ">" $sRNAs_fasta | sort | uniq -d`;
chomp $duplicate_fasta_header;
die("\nError: Duplicate organisms ($duplicate_fasta_header) are present in $sRNAs_fasta.\n\n") if($duplicate_fasta_header);

# write input options to file
open WRITETOOPTIONS, ">", "CopraRNA_option_file.txt";
    print WRITETOOPTIONS "sRNA FASTA:" . $sRNAs_fasta . "\n";
    print WRITETOOPTIONS "nt upstream:" . $upstream . "\n";
    print WRITETOOPTIONS "nt downstream:" . $downstream . "\n";
    print WRITETOOPTIONS "region:" . $region . "\n";
    print WRITETOOPTIONS "relative clustersize:" . $RelClusterSize . "\n"; 
    print WRITETOOPTIONS "core count:" . $core_count . "\n";
    print WRITETOOPTIONS "win size:" . $winsize . "\n";
    print WRITETOOPTIONS "max bp dist:" . $maxbpdist . "\n";
    print WRITETOOPTIONS "CopraRNA1:" . $cop1 . "\n";
    print WRITETOOPTIONS "verbose:" . $verbose . "\n";
    print WRITETOOPTIONS "websrv:" . $websrv . "\n";
    print WRITETOOPTIONS "nooi:" . $nooi . "\n";
    print WRITETOOPTIONS "top count:" . $topcount . "\n";
    print WRITETOOPTIONS "root:" . $root . "\n";
    print WRITETOOPTIONS "enrich:" . $enrich . "\n";
    print WRITETOOPTIONS "noclean:" . $noclean . "\n";
    print WRITETOOPTIONS "cons:" . $cons . "\n";
    print WRITETOOPTIONS "ooifilt:" . $ooi_filt . "\n"; ## 
    print WRITETOOPTIONS "version:CopraRNA ".$COPRARNA_VERSION."\n";
    print WRITETOOPTIONS "genomePath:$genomePath\n";
	print WRITETOOPTIONS "temperature:$temperature\n";
close WRITETOOPTIONS;
# end write options

# CopraRNA error log
system "touch err.log";

system "cp $sRNAs_fasta input_sRNA.fa" unless ($sRNAs_fasta eq "input_sRNA.fa");
$sRNAs_fasta = "input_sRNA.fa";

# format sRNA fasta - put sequence in 1 line
system $PATH_COPRA . "coprarna_aux/format_fasta.pl $sRNAs_fasta" . " > $sRNAs_fasta.temp";
system "mv $sRNAs_fasta.temp $sRNAs_fasta";

# build RefSeq input based on the sRNA input fasta (can only contain refseq IDs in header)
my $RefSeqIds = `grep '>' $sRNAs_fasta | sed 's/>//g' | tr '\n' ' '`;

# print org of interest
if ($verbose) {
    my $ooi_rid = `grep ">" input_sRNA.fa | head -n1 | sed 's/>//g'`;
    chomp $ooi_rid;
    my $full_ooi = `grep '$ooi_rid' "$PATH_COPRA/coprarna_aux/CopraRNA_available_organisms.txt"`;
    chomp $full_ooi;
    print "\nOrganism of interest: $full_ooi\n\n";
}

my $homology_intaRNA_call=$PATH_COPRA . "coprarna_aux/homology_intaRNA.pl $sRNAs_fasta $upstream $downstream $region $RefSeqIds";
print $homology_intaRNA_call . "\n" if ($verbose);
my $homology_intaRNA_exitStatus = system $homology_intaRNA_call;
$homology_intaRNA_exitStatus /= 256; # get original exit value
# check exit status
if ($homology_intaRNA_exitStatus != 0) { 
	die ("\nERROR: homology_intaRNA.pl returned with exit code $homology_intaRNA_exitStatus. Something went wrong, so please check the error files!\n\n");
}

# get organism of interest
my $ncrnaRIDs = `grep ">" ncrna.fa | sed 's/>ncRNA_//g' | tr '\n' ' '`;
my @splitRID = split(/\s/, $ncrnaRIDs);
my $organismOfInterest = $splitRID[0];
chomp $organismOfInterest;
# final optimal IntaRNA result for organism of interest
my $MainFinalCSV = $organismOfInterest . "_upfromstartpos_" . $upstream . "_down_" . $downstream . "_opt.intarna.csv";

if ($enrich) {
	############################################################
    print "Performing auxiliary enrichment\n" if ($verbose);
	############################################################
    # add IntaRNA single organisms chart reports for aux enrichment // sort by p-value
    system "env LC_ALL=C sort -t';' -g -k36 $MainFinalCSV -o intarna_websrv_table.csv";
    system $PATH_COPRA . "coprarna_aux/add_GI_genename_annotation_intarna.pl";
    system $PATH_COPRA . "coprarna_aux/DAVIDWebService_IntaRNA_chartReport.py intarna_websrv_table_ncbi.csv $enrich > IntaRNA_chartReport.txt"; ## aux einrich for same amout as regular enrichment
    system "grep -P 'geneIds\\s=|termName\\s=' IntaRNA_chartReport.txt | sed 's/^[ ]*//g' | sed 's/ = /=/g' | sed 's/, /,/g' | sed 's/\"//g' > IntaRNA_chartReport_grepped.txt";
    system $PATH_COPRA . "coprarna_aux/find_single_specific_targets_in_termCluster.pl > org_of_interest_aux_enrichment.txt";
    system "echo 'locus_tag,start_tar,stop_tar,start_query,stop_query,energy,p-value,gene_name,gene_id,annotation,functional_terms' > aux_table.csv";
    system "awk -F';' '{ print \$1\",\"\$9\",\"\$10\",\"\$11\",\"\$12\",\"\$15\",\"\$36\",\"\$37\",\"\$38\",\"\$39 }' intarna_websrv_table_ncbi.csv > intarna_websrv_table_ncbi_awk.csv";
    my $aux_gids = `grep -oP ';\\d+\\(' org_of_interest_aux_enrichment.txt | sed 's/[;(]//g' | sort -u | tr '\n' ';'`;
    chop $aux_gids; # remove trailing ';' 
    my @split_aux_gids = split(/;/, $aux_gids);
    foreach(@split_aux_gids) {
        system "grep -P ',$_,' intarna_websrv_table_ncbi_awk.csv | tr '\n' ',' >> aux_table.csv";
        system "grep -P '$_' org_of_interest_aux_enrichment.txt | awk -F';' '{ print \$1 }' | tr '\n' ';' | sed 's/,/ /' | sed 's/.\$//' >> aux_table.csv";
        system "echo >> aux_table.csv";
    }
}

# output warnings
system "awk -F ';' '{if (\$2 > 0.5) { print toupper(\$1) \" may be overweighted. It has weight\"; printf(\"\%.2f\", \$2); print \". You should consider checking the 16S rDNA tree. We suggest removal of outliers from your input and restarting.\";} }' zscore.weight | tr '\n' ' ' > weights.warning";

# check err.log // should be empty // err.log contains information on 
# 1. not correctly downloaded RefSeq files 
# 2. gene no CDS issue 
# 3. wrong 16S counts
# 4. empty CopraRNA_result.csv 
# 5. the exception in add_pval_to_csv_evdfit.R
# -s  File has nonzero size (returns size in bytes).
if (-s "err.log") { die("\nError: CopraRNA failed. Check err.log for details.\n\n"); } ## added another check here at the bottom maybe we need some more check hooks in the new scripts

# create regions plots
print "Preparing interaction plots\n" if ($verbose);
system "R --slave -f " . $PATH_COPRA . "coprarna_aux/script_R_plots_8.R --args CopraRNA_result_all.csv $topcount 2> /dev/null > /dev/null"; ## changed input file and piping command line output to /dev/null for silencing // 

# convert postscript files to PNG

# thumbnails png
if ($websrv) {
    system "convert -size 170x170 -resize 170x170 -flatten -rotate 90 sRNA_regions_with_histogram.ps thumbnail_sRNA.png";
    system "convert -size 170x170 -resize 170x170 -flatten -rotate 90 mRNA_regions_with_histogram.ps thumbnail_mRNA.png";
}

# blow up images png
system "convert -density '300' -resize '700' -flatten -rotate 90 sRNA_regions_with_histogram.ps sRNA_regions_with_histogram.png";
system "convert -density '300' -resize '700' -flatten -rotate 90 mRNA_regions_with_histogram.ps mRNA_regions_with_histogram.png";

# clean up
unless ($noclean) {

    print "Cleaning run directory\n" if ($verbose);
	system "bash $PATH_COPRA/coprarna_aux/copraRNA_cleanupWD.sh";

}

