use core::starknet::ContractAddress;

//to do : return the nft id and token uri in the get function

#[starknet::interface]
pub trait IAttenSysCourse<TContractState> {
    fn create_course(
        ref self: TContractState,
        owner_: ContractAddress,
        accessment_: bool,
        base_uri: ByteArray,
        name_: ByteArray,
        symbol: ByteArray,
        course_ipfs_uri: ByteArray
    ) -> ContractAddress;
    fn add_replace_course_content(
        ref self: TContractState,
        course_identifier: u256,
        owner_: ContractAddress,
        new_course_uri_a: felt252,
        new_course_uri_b: felt252
    );
    //untested
    fn finish_course_claim_certification(ref self: TContractState, course_identifier: u256);
    //untested
    fn check_course_completion_status_n_certification(
        self: @TContractState, course_identifier: u256, candidate: ContractAddress
    ) -> bool;
    fn get_course_infos(
        self: @TContractState, course_identifiers: Array<u256>
    ) -> Array<AttenSysCourse::Course>;
    //untested
    fn get_user_completed_courses(self: @TContractState, user: ContractAddress) -> Array<u256>;
    fn get_all_courses_info(self: @TContractState) -> Array<AttenSysCourse::Course>;
    fn get_all_creator_courses(
        self: @TContractState, owner_: ContractAddress
    ) -> Array<AttenSysCourse::Course>;
    fn get_creator_info(self: @TContractState, creator: ContractAddress) -> AttenSysCourse::Creator;
    fn get_course_nft_contract(self: @TContractState, course_identifier: u256) -> ContractAddress;
    fn transfer_admin(ref self: TContractState, new_admin: ContractAddress);
    fn claim_admin_ownership(ref self: TContractState);
    fn get_admin(self: @TContractState) -> ContractAddress;
    fn get_new_admin(self: @TContractState) -> ContractAddress;
    fn get_total_course_completions(self: @TContractState, course_identifier: u256) -> u256;
}

//Todo, make a count of the total number of users that finished the course.

#[starknet::interface]
pub trait IAttenSysNft<TContractState> {
    // NFT contract
    fn mint(ref self: TContractState, recipient: ContractAddress, token_id: u256);
}

#[starknet::contract]
pub mod AttenSysCourse {
    use super::IAttenSysNftDispatcherTrait;
    use core::starknet::{
        ContractAddress, get_caller_address, syscalls::deploy_syscall, ClassHash,
        contract_address_const
    };
    use core::starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
        MutableVecTrait
    };


    #[event]
    #[derive(starknet::Event, Clone, Debug, Drop)]
    pub enum Event {
        CourseCreated: CourseCreated,
        CourseReplaced: CourseReplaced,
        CourseCertClaimed: CourseCertClaimed,
        AdminTransferred: AdminTransferred,
    }

    #[derive(starknet::Event, Clone, Debug, Drop)]
    pub struct CourseCreated {
        pub course_identifier: u256,
        pub owner_: ContractAddress,
        pub accessment_: bool,
        pub base_uri: ByteArray,
        pub name_: ByteArray,
        pub symbol: ByteArray,
        pub course_ipfs_uri: ByteArray,
    }

    #[derive(starknet::Event, Clone, Debug, Drop)]
    pub struct CourseReplaced {
        pub course_identifier: u256,
        pub owner_: ContractAddress,
        pub new_course_uri_a: felt252,
        pub new_course_uri_b: felt252,
    }

    #[derive(starknet::Event, Clone, Debug, Drop)]
    pub struct CourseCertClaimed {
        pub course_identifier: u256,
        pub candidate: ContractAddress,
    }

    #[derive(starknet::Event, Clone, Debug, Drop)]
    pub struct AdminTransferred {
        pub new_admin: ContractAddress,
    }

    #[storage]
    struct Storage {
        //save content creator info including all all contents created.
        course_creator_info: Map::<ContractAddress, Creator>,
        //saves specific course (course details only), set this when creating course
        specific_course_info_with_identifer: Map::<u256, Course>,
        //saves all course info
        all_course_info: Vec<Course>,
        //saves a course completion status after successfully completed a particular course
        completion_status: Map::<(ContractAddress, u256), bool>,
        //saves completed courses by user
        completed_courses: Map::<ContractAddress, Vec<u256>>,
        //saves identifier tracker
        identifier_tracker: u256,
        //maps, creator's address to an array of struct of all courses created.
        creator_to_all_content: Map::<ContractAddress, Vec<Course>>,
        //nft classhash
        hash: ClassHash,
        //admin address
        admin: ContractAddress,
        // address of intended new admin
        intended_new_admin: ContractAddress,
        //saves nft contract address associated to event
        course_nft_contract_address: Map::<u256, ContractAddress>,
        //tracks all minted nft id minted by events
        track_minted_nft_id: Map::<(u256, ContractAddress), u256>,
    }
    //find a way to keep track of all course identifiers for each owner.
    #[derive(Drop, Serde, starknet::Store)]
    pub struct Creator {
        pub address: ContractAddress,
        pub number_of_courses: u256,
        pub creator_status: bool,
    }

    //consider the idea of having the uri for each course within the course struct.

    #[derive(Drop, Clone, Serde, starknet::Store)]
    pub struct Course {
        pub owner: ContractAddress,
        pub course_identifier: u256,
        pub accessment: bool,
        pub uri: Uri,
        pub course_ipfs_uri: ByteArray,
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub struct Uri {
        pub first: felt252,
        pub second: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, _hash: ClassHash) {
        self.admin.write(owner);
        self.hash.write(_hash);
    }

    #[abi(embed_v0)]
    impl IAttenSysCourseImpl of super::IAttenSysCourse<ContractState> {
        fn create_course(
            ref self: ContractState,
            owner_: ContractAddress,
            accessment_: bool,
            base_uri: ByteArray,
            name_: ByteArray,
            symbol: ByteArray,
            course_ipfs_uri: ByteArray
        ) -> ContractAddress {
            //make an address zero check
            let identifier_count = self.identifier_tracker.read();
            let current_identifier = identifier_count + 1;
            let mut current_creator_info: Creator = self.course_creator_info.entry(owner_).read();
            if current_creator_info.number_of_courses > 0 {
                assert(owner_ == get_caller_address(), 'not owner');
                current_creator_info.number_of_courses += 1;
            } else {
                current_creator_info.address = owner_;
                current_creator_info.number_of_courses += 1;
                current_creator_info.creator_status = true;
            }
            let empty_uri = Uri { first: '', second: '', };
            let mut course_call_data: Course = Course {
                owner: owner_,
                course_identifier: current_identifier,
                accessment: accessment_,
                uri: empty_uri,
                course_ipfs_uri: course_ipfs_uri.clone()
            };

            self.creator_to_all_content.entry(owner_).append().write(Course {
                owner: owner_,
                course_identifier: current_identifier,
                accessment: accessment_,
                uri: empty_uri,
                course_ipfs_uri: course_ipfs_uri.clone()
            });
            self.course_creator_info.entry(owner_).write(current_creator_info);
            self
                .specific_course_info_with_identifer
                .entry(current_identifier)
                .write(course_call_data);
            self.identifier_tracker.write(current_identifier);
            // constructor arguments
            let mut constructor_args = array![];
            base_uri.serialize(ref constructor_args);
            name_.serialize(ref constructor_args);
            symbol.serialize(ref constructor_args);
            let contract_address_salt: felt252 = current_identifier.try_into().unwrap();

            //deploy contract
            let (deployed_contract_address, _) = deploy_syscall(
                self.hash.read(), contract_address_salt, constructor_args.span(), false
            )
                .expect('failed to deploy_syscall');
            self
                .track_minted_nft_id
                .entry((current_identifier, deployed_contract_address))
                .write(1);
            self
                .course_nft_contract_address
                .entry(current_identifier)
                .write(deployed_contract_address);

            self
                .emit(
                    CourseCreated {
                        course_identifier: current_identifier,
                        owner_: owner_,
                        accessment_: accessment_,
                        base_uri: base_uri,
                        name_: name_,
                        symbol: symbol,
                        course_ipfs_uri: course_ipfs_uri,
                    }
                );
            deployed_contract_address
        }


        //from frontend, the idea will be to obtain the previous uri, transfer content from the
        //previous uri to the new uri
        // and write the new uri to state.
        fn add_replace_course_content(
            ref self: ContractState,
            course_identifier: u256,
            owner_: ContractAddress,
            new_course_uri_a: felt252,
            new_course_uri_b: felt252
        ) {
            let mut current_course_info: Course = self
                .specific_course_info_with_identifer
                .entry(course_identifier)
                .read();
            let pre_existing_counter = self.identifier_tracker.read();
            assert(course_identifier <= pre_existing_counter, 'course non-existent');
            assert(current_course_info.owner == get_caller_address(), 'not owner');
            let call_data: Uri = Uri { first: new_course_uri_a, second: new_course_uri_b, };
            current_course_info.uri = call_data;
            self
                .specific_course_info_with_identifer
                .entry(course_identifier)
                .write(current_course_info.clone());

            //run a loop to check if course ID exists in all course info vece, if it does, replace
            //the uris.
            if self.all_course_info.len() == 0 {
                self.all_course_info.append().write(current_course_info.clone());
            } else {
                for i in 0
                    ..self
                        .all_course_info
                        .len() {
                            if self
                                .all_course_info
                                .at(i)
                                .read()
                                .course_identifier == course_identifier {
                                self.all_course_info.at(i).uri.write(call_data);
                            } else {
                                self.all_course_info.append().write(current_course_info.clone());
                            }
                        };
            };
            //run a loop to update the creator content storage data
            let mut i: u64 = 0;
            let vec_len = self.creator_to_all_content.entry(owner_).len();
            loop {
                if i >= vec_len {
                    break;
                }
                let content = self.creator_to_all_content.entry(owner_).at(i).read();
                if content.course_identifier == course_identifier {
                    self.creator_to_all_content.entry(owner_).at(i).uri.write(call_data);
                }
                i += 1;
            };
            self
                .emit(
                    CourseReplaced {
                        course_identifier: course_identifier,
                        owner_: owner_,
                        new_course_uri_a: new_course_uri_a,
                        new_course_uri_b: new_course_uri_b,
                    }
                );
        }

        fn finish_course_claim_certification(ref self: ContractState, course_identifier: u256) {
            //only check for accessment score. that is if there's assesment
            //todo : verifier check, get a value from frontend, confirm the hash if it matches with
            //what is being saved. goal is to avoid fraudulent course claim.
            //todo issue certification. (whitelist address)
            self.completion_status.entry((get_caller_address(), course_identifier)).write(true);
            self.completed_courses.entry(get_caller_address()).append().write(course_identifier);
            let nft_contract_address = self
                .course_nft_contract_address
                .entry(course_identifier)
                .read();

            let nft_dispatcher = super::IAttenSysNftDispatcher {
                contract_address: nft_contract_address
            };

            let nft_id = self
                .track_minted_nft_id
                .entry((course_identifier, nft_contract_address))
                .read();
            nft_dispatcher.mint(get_caller_address(), nft_id);
            self
                .track_minted_nft_id
                .entry((course_identifier, nft_contract_address))
                .write(nft_id + 1);
            self
                .emit(
                    CourseCertClaimed {
                        course_identifier: course_identifier, candidate: get_caller_address(),
                    }
                );
        }


        fn check_course_completion_status_n_certification(
            self: @ContractState, course_identifier: u256, candidate: ContractAddress
        ) -> bool {
            self.completion_status.entry((candidate, course_identifier)).read()
        }

        fn get_course_infos(
            self: @ContractState, course_identifiers: Array<u256>
        ) -> Array<Course> {
            let mut course_info_list: Array<Course> = array![];
            for element in course_identifiers {
                let mut data = self.specific_course_info_with_identifer.entry(element).read();
                course_info_list.append(data);
            };
            course_info_list
        }

        fn get_user_completed_courses(self: @ContractState, user: ContractAddress) -> Array<u256> {
            let vec = self.completed_courses.entry(user);
            let mut arr = array![];
            let len = vec.len();
            let mut i: u64 = 0;
            loop {
                if i >= len {
                    break;
                }
                if let Option::Some(element) = vec.get(i) {
                    arr.append(element.read());
                }
                i += 1;
            };
            arr
        }

        fn get_all_courses_info(self: @ContractState) -> Array<Course> {
            let mut arr = array![];
            for i in 0
                ..self.all_course_info.len() {
                    arr.append(self.all_course_info.at(i).read());
                };
            arr
        }

        fn get_all_creator_courses(self: @ContractState, owner_: ContractAddress) -> Array<Course> {
            let vec = self.creator_to_all_content.entry(owner_);
            let mut arr = array![];
            let len = vec.len();
            let mut i: u64 = 0;
            loop {
                if i >= len {
                    break;
                }
                if let Option::Some(element) = vec.get(i) {
                    arr.append(element.read());
                }
                i += 1;
            };
            arr
        }

        fn get_creator_info(self: @ContractState, creator: ContractAddress) -> Creator {
            self.course_creator_info.entry(creator).read()
        }

        fn get_course_nft_contract(
            self: @ContractState, course_identifier: u256
        ) -> ContractAddress {
            self.course_nft_contract_address.entry(course_identifier).read()
        }

        fn transfer_admin(ref self: ContractState, new_admin: ContractAddress) {
            assert(new_admin != self.zero_address(), 'zero address not allowed');
            assert(get_caller_address() == self.admin.read(), 'unauthorized caller');

            self.intended_new_admin.write(new_admin);
            self.emit(AdminTransferred { new_admin: new_admin });
        }

        fn claim_admin_ownership(ref self: ContractState) {
            assert(get_caller_address() == self.intended_new_admin.read(), 'unauthorized caller');

            self.admin.write(self.intended_new_admin.read());
            self.intended_new_admin.write(self.zero_address());
        }

        fn get_admin(self: @ContractState) -> ContractAddress {
            self.admin.read()
        }

        fn get_new_admin(self: @ContractState) -> ContractAddress {
            self.intended_new_admin.read()
        }

        fn get_total_course_completions(self: @ContractState, course_identifier: u256) -> u256 {
            let nft_contract_address = self
                .course_nft_contract_address
                .entry(course_identifier)
                .read();
            let next_nft_id = self
                .track_minted_nft_id
                .entry((course_identifier, nft_contract_address))
                .read();

            if next_nft_id <= 1 {
                0
            } else {
                next_nft_id - 1
            }
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn zero_address(self: @ContractState) -> ContractAddress {
            contract_address_const::<0>()
        }
    }
}

