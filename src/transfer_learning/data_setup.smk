"""Setup the data for transfer-learning
"""
workdir:
    "../../"
from kipoi.utils import read_txt
import pandas as pd

valid_chr = ['chr1', 'chr8', 'chr21']
test_chr = ['chr9']

all_labels = pd.Series(read_txt("data/raw/tlearn/metadata/all_tasks.txt"))
eval_labels = read_txt("data/raw/tlearn/metadata/eval_tasks.txt")


rule all:
    input:
        expand("data/processed/tlearn/data/{split}/{task}/interval_labels.tsv.gz",
               split=['train', 'valid', 'test'],
               task=eval_labels),
        expand("data/processed/tlearn/models/transferred/{task}/weights.01.hdf5",
               task=eval_labels)

# --------------------------------------------
grep_regex = {
    "train": "-vwE " + "'^" + "|^".join(valid_chr + test_chr) + "'",
    "valid": "-wE " + "'^" + "|^".join(valid_chr) + "'",
    "test": "-wE " + "'^" + "|^".join(test_chr) + "'",
}

rule data_split:
    """Split the data w.r.t train, validation and test as well as by task
    """
    input:
        f = "data/raw/tlearn/intervals_files_complete.tsv.gz"
    output:
        f = "data/processed/tlearn/data/{split}/{task}/interval_labels.tsv.gz"
    params:
        regex_str = lambda w: grep_regex[w.split],
        col_id = lambda w: str(4 + all_labels.index[all_labels == w.task][0])
    shell:
        """
        zcat {input.f} | \
          grep {params.regex_str} | \
          cut -f1,2,3,{params.col_id} | \
          gzip -c > '{output.f}'
        """

# TODO - train the model
rule train_model:
    input:
        train = "data/processed/tlearn/data/train/{task}/interval_labels.tsv.gz",
        valid = "data/processed/tlearn/data/valid/{task}/interval_labels.tsv.gz",
        fasta = "data/raw/dataloader_files/shared/hg19.fa",
    output:
        model = "data/processed/tlearn/models/transferred/{task}/weights.01.hdf5",
        history = "data/processed/tlearn/models/transferred/{task}/history.csv"
    params:
        dl_kwargs_train = lambda w, input, output: json.dumps({"intervals_file": input.train,
                                                    "fasta_file": input.fasta, 
                                                    "num_chr_fasta": True}),
        dl_kwargs_eval = lambda w, input, output: json.dumps({"intervals_file": input.valid,
                                                   "fasta_file": input.fasta,
                                                   "num_chr_fasta": True}),
        outdir = lambda w, output: os.path.dirname(output.model)
    shell:
        """
        python src/transfer_learning/tlearn.py \
          models/Divergent421 --source=dir \
          --dl_kwargs_train='{params.dl_kwargs_train}' \
          --dl_kwargs_eval='{params.dl_kwargs_eval}' \
          -t 1 \
          -o '{params.outdir}' \
          --transfer_to=prelu_5 \
          --freeze_to=dense_2 \
          --batch_size=128 \
          -n 8 \
          -p 1
        """