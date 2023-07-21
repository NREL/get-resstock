#!/bin/bash

#SBATCH -t 1:00
#SBATCH --job-name=node_rollcall
#SBATCH --output=node_rollcall.%j.out
#SBATCH --nodes=10
#SBATCH --ntasks-per-node=1
echo "Running on $SLURM_JOB_NUM_NODES nodes: $SLURM_NODELIST"
module load conda
conda activate /shared-projects/buildstock/envs/buildstock-2023.01.0/
buildstock_eagle project_CA/CA_baseline.yml