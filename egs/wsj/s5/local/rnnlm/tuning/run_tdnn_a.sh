#!/bin/bash

# Copyright 2012  Johns Hopkins University (author: Daniel Povey)  Tony Robinson
#           2015  Guoguo Chen

# This script trains LMs on the WSJ LM-training data.
# It requires that you have already run wsj_extend_dict.sh,
# to get the larger-size dictionary including all of CMUdict
# plus any OOVs and possible acronyms that we could easily
# derive pronunciations for.

# This script takes no command-line arguments but takes the --cmd option.

# Begin configuration section.
cmd=run.pl
dir=exp/rnnlm_tdnn_a
embedding_dim=600
stage=0
train_stage=0

. utils/parse_options.sh


text=data/local/dict_nosp_larger/cleaned.gz
lexicon=data/local/dict_nosp_larger/lexiconp.txt
text_dir=data/rnnlm/text_nosp
mkdir -p $dir/config
set -e

for f in $text $lexicon; do
  [ ! -f $f ] && \
    echo "$0: expected file $f to exist; search for local/wsj_extend_dict.sh in run.sh" && exit 1
done

if [ $stage -le 0 ]; then
  mkdir -p $text_dir
  echo -n >$text_dir/dev.txt
  # hold out one in every 500 lines as dev data.
  gunzip -c data/local/dict_nosp_larger/cleaned.gz  | awk -v text_dir=$text_dir '{if(NR%500 == 0) { print >text_dir"/dev.txt"; } else {print;}}' >$text_dir/wsj.txt
fi

if [ $stage -le 1 ]; then
  # the training scripts require that <s>, </s> and <brk> be present in a particular
  # order.
  awk '{print $1}' $lexicon | sort | uniq | \
    awk 'BEGIN{print "<eps> 0";print "<s> 1"; print "</s> 2"; print "<brk> 3";n=4;} {print $1, n++}' \
        >$dir/config/words.txt
  # words that are not present in words.txt but are in the training or dev data, will be
  # mapped to <SPOKEN_NOISE> during training.
  echo "<SPOKEN_NOISE>" >$dir/config/oov.txt

  cat > $dir/config/data_weights.txt <<EOF
wsj   1   1.0
EOF

  rnnlm/get_unigram_probs.py --vocab-file=$dir/config/words.txt \
                             --unk-word="<SPOKEN_NOISE>" \
                             --data-weights-file=$dir/config/data_weights.txt \
                             $text_dir >$dir/config/unigram_probs.txt

  # choose features
  rnnlm/choose_features.py --unigram-probs=$dir/config/unigram_probs.txt \
                           --use-constant-feature=true \
                           --special-words='<s>,</s>,<brk>,<SPOKEN_NOISE>' \
                           $dir/config/words.txt > $dir/config/features.txt

  cat >$dir/config/xconfig <<EOF
input dim=$embedding_dim name=input
relu-renorm-layer name=tdnn1 dim=600 input=Append(0, IfDefined(-1))
relu-renorm-layer name=tdnn2 dim=600 input=Append(0, IfDefined(-1))
relu-renorm-layer name=tdnn3 dim=600 input=Append(0, IfDefined(-2))
output-layer name=output include-log-softmax=false dim=$embedding_dim
EOF
  rnnlm/validate_config_dir.sh $text_dir $dir/config
fi

if [ $stage -le 2 ]; then
  rnnlm/prepare_rnnlm_dir.sh $text_dir $dir/config $dir
fi

if [ $stage -le 3 ]; then
  rnnlm/train_rnnlm.sh --num-jobs-initial 1 --num-jobs-final 3 \
                  --stage $train_stage --num-epochs 10 --cmd "queue.pl" $dir
fi

exit 0
