-- FSTORE-1020
ALTER TABLE `hopsworks`.`training_dataset_filter_condition` DROP FOREIGN KEY `tdfc_feature_group_fk`;
ALTER TABLE `hopsworks`.`training_dataset_filter_condition` ADD FOREIGN KEY `tdfc_feature_group_fk`(`feature_group_id`)
    REFERENCES `hopsworks`.`feature_group` (`id`)
    ON DELETE SET NULL ON UPDATE NO ACTION;

ALTER TABLE `hopsworks`.`conda_commands` MODIFY COLUMN `created` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3);

DROP TABLE `hopsworks`.`pia`;

ALTER TABLE `hopsworks`.`oauth_client` ADD COLUMN `given_name_claim` VARCHAR(255) NOT NULL DEFAULT 'given_name';
ALTER TABLE `hopsworks`.`oauth_client` ADD COLUMN `family_name_claim` VARCHAR(255) NOT NULL DEFAULT 'family_name';
ALTER TABLE `hopsworks`.`oauth_client` ADD COLUMN `email_claim` VARCHAR(255) NOT NULL DEFAULT 'email';
ALTER TABLE `hopsworks`.`oauth_client` ADD COLUMN `group_claim` VARCHAR(255) DEFAULT NULL;

-- FSTORE-980: helper columns for feature view
ALTER TABLE `hopsworks`.`training_dataset_feature` ADD COLUMN `inference_helper_column` tinyint(1) DEFAULT '0';
ALTER TABLE `hopsworks`.`training_dataset_feature` ADD COLUMN `training_helper_column` tinyint(1) DEFAULT '0';


-- Rstudio updates
ALTER TABLE `hopsworks`.`rstudio_project` DROP COLUMN `host_ip`,
    DROP COLUMN `token`;

ALTER TABLE `hopsworks`.`rstudio_project` ADD COLUMN `login_password` varchar(255) CHARACTER SET latin1 COLLATE latin1_general_cs DEFAULT NULL;
ALTER TABLE `hopsworks`.`rstudio_project` ADD COLUMN `login_username` varchar(255) CHARACTER SET latin1 COLLATE latin1_general_cs DEFAULT NULL;

ALTER TABLE `hopsworks`.`rstudio_project` MODIFY COLUMN `pid` varchar(255) CHARACTER SET latin1 COLLATE latin1_general_cs DEFAULT NULL;

ALTER TABLE `hopsworks`.`rstudio_settings`
    DROP COLUMN num_tf_ps, DROP COLUMN num_tf_gpus,
    DROP COLUMN num_mpi_np, DROP COLUMN appmaster_cores,
    DROP COLUMN appmaster_memory, DROP COLUMN num_executors,
    DROP COLUMN num_executor_cores, DROP COLUMN executor_memory,
    DROP COLUMN dynamic_initial_executors, DROP COLUMN dynamic_min_executors,
    DROP COLUMN dynamic_max_executors, DROP COLUMN log_level,
    DROP COLUMN mode, DROP COLUMN umask,
    DROP COLUMN archives, DROP COLUMN jars,
    DROP COLUMN files, DROP COLUMN py_files,
    DROP COLUMN spark_params;

ALTER TABLE `hopsworks`.`rstudio_settings` ADD COLUMN  `base_dir` varchar(255) COLLATE latin1_general_cs DEFAULT NULL;
ALTER TABLE `hopsworks`.`rstudio_settings` ADD COLUMN  `job_config` varchar(11000) COLLATE latin1_general_cs DEFAULT NULL;
ALTER TABLE `hopsworks`.`rstudio_settings` ADD COLUMN  `docker_config` varchar(1000) COLLATE latin1_general_cs DEFAULT NULL;

ALTER TABLE `hopsworks`.`project` ADD COLUMN `rstudio_docker_image` VARCHAR(255) COLLATE latin1_general_cs DEFAULT NULL;

CREATE TABLE `rstudio_environment_build` (
                                             `id` int NOT NULL AUTO_INCREMENT,
                                             `build_script` varchar(1000) CHARACTER SET latin1 COLLATE latin1_general_cs NOT NULL,
                                             `user` int NOT NULL,
                                             `project` int NOT NULL,
                                             `build_start` bigint DEFAULT NULL,
                                             `build_finish` bigint DEFAULT NULL,
                                             `build_result` varchar(128) CHARACTER SET latin1 COLLATE latin1_general_cs NOT NULL,
                                             `secret` varchar(255) CHARACTER SET latin1 COLLATE latin1_general_cs NOT NULL,
                                             `logFile` varchar(1000) CHARACTER SET latin1 COLLATE latin1_general_cs DEFAULT NULL,
                                             `build_name` varchar(255) CHARACTER SET latin1 COLLATE latin1_general_cs DEFAULT NULL,
                                             `description` varchar(1000) CHARACTER SET latin1 COLLATE latin1_general_cs DEFAULT NULL,
                                             PRIMARY KEY (`id`),
                                             KEY `user_fk` (`user`),
                                             KEY `rstudio_env_build_project_fk` (`project`),
                                             CONSTRAINT `rstudio_env_build_project_fk` FOREIGN KEY (`project`) REFERENCES `project` (`id`) ON DELETE CASCADE,
                                             CONSTRAINT `rstudio_env_build_usr_fkc` FOREIGN KEY (`user`) REFERENCES `users` (`uid`) ON DELETE CASCADE
) ENGINE=ndbcluster AUTO_INCREMENT=5154 DEFAULT CHARSET=latin1;