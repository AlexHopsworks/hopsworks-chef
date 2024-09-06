-- HWORKS-987
ALTER TABLE `hopsworks`.`model_version` ADD CONSTRAINT `model_version_key` UNIQUE (`model_id`,`version`);
ALTER TABLE `hopsworks`.`model_version` DROP PRIMARY KEY;
ALTER TABLE `hopsworks`.`model_version` ADD COLUMN id int(11) AUTO_INCREMENT PRIMARY KEY;

-- FSTORE-1190
ALTER TABLE `hopsworks`.`embedding_feature`
    ADD COLUMN `model_version_id` INT(11) NULL;

ALTER TABLE `hopsworks`.`embedding_feature`
    ADD CONSTRAINT `embedding_feature_model_version_fk` FOREIGN KEY (`model_version_id`) REFERENCES `model_version` (`id`) ON DELETE SET NULL ON UPDATE NO ACTION;

ALTER TABLE `hopsworks`.`serving` ADD COLUMN `api_protocol` TINYINT(1) NOT NULL DEFAULT '0';

-- FSTORE-1096
ALTER TABLE `hopsworks`.`feature_store_jdbc_connector`
    ADD COLUMN `secret_uid` INT DEFAULT NULL,
    ADD COLUMN `secret_name` VARCHAR(200) DEFAULT NULL;

-- FSTORE-1248
ALTER TABLE `hopsworks`.`executions`
    ADD COLUMN `notebook_out_path` varchar(255) COLLATE latin1_general_cs DEFAULT NULL;

CREATE TABLE IF NOT EXISTS `hopsworks`.`model_link` (
  `id` int NOT NULL AUTO_INCREMENT,
  `model_version_id` int(11) NOT NULL,
  `parent_training_dataset_id` int(11),
  `parent_feature_store` varchar(100) NOT NULL,
  `parent_feature_view_name` varchar(63) NOT NULL,
  `parent_feature_view_version` int(11) NOT NULL,
  `parent_training_dataset_version` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `link_unique` (`model_version_id`, `parent_training_dataset_id`),
  KEY `model_version_id_fkc` (`model_version_id`),
  KEY `parent_training_dataset_id_fkc` (`parent_training_dataset_id`),
  CONSTRAINT `model_version_id_fkc` FOREIGN KEY (`model_version_id`) REFERENCES `hopsworks`.`model_version` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `training_dataset_parent_fkc` FOREIGN KEY (`parent_training_dataset_id`) REFERENCES `hopsworks`.`training_dataset` (`id`) ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=ndbcluster DEFAULT CHARSET=latin1 COLLATE=latin1_general_cs;

-- FSTORE-920
ALTER TABLE `hopsworks`.`feature_store_jdbc_connector`
    ADD `driver_path` VARCHAR(2000) DEFAULT NULL;

-- HWORKS-1235
ALTER TABLE `hopsworks`.`serving` ADD COLUMN `deployed_by` int(11) DEFAULT NULL;
ALTER TABLE `hopsworks`.`serving` ADD KEY `deployed_by_fk` (`deployed_by`);
ALTER TABLE `hopsworks`.`serving` ADD CONSTRAINT `deployed_by_fk_serving` FOREIGN KEY (`deployed_by`) REFERENCES `users` (`uid`) ON DELETE CASCADE ON UPDATE NO ACTION;

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